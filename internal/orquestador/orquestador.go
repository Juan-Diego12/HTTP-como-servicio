// Package orquestador coordina el ciclo de vida de las instancias: valida, asigna IP,
// llama al Ejecutor (scripts reales o simulación), maneja estados y guarda todo en JSON.
package orquestador

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

// Config de la plataforma.
type Config struct {
	ArchivoDatos string // JSON con las instancias
	DirSubidas   string // donde se guardan los .zip recibidos
	Dominio      string // cloud.local
	Red          string // 192.168.10
	PrimeraIP    int    // 30
	UltimaIP     int    // 254
	Modo         string // "simulado" o "real"
}

// Orquestador es el componente central de la app.
type Orquestador struct {
	cfg        Config
	ej         Ejecutor
	mu         sync.Mutex // protege instancias y el archivo JSON
	instancias map[string]*Instancia
	cola       sync.Mutex // una operación de infraestructura a la vez (VBoxManage, nsupdate)
}

// Hostname válido (RFC 1123), en minúsculas: letras, números y guiones, sin guion al inicio ni al final.
var reHostname = regexp.MustCompile(`^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$`)

// Nombres que no pueden usar los usuarios (servidor DNS, plantilla y similares).
var reservados = map[string]bool{
	"ns": true, "www": true, "localhost": true, "apacheserver": true, "plantilla": true,
}

// Errores de validación (la interfaz los muestra tal cual).
var (
	ErrNoExiste = errors.New("la instancia no existe")
	ErrOcupada  = errors.New("la instancia tiene una operación en curso; espere a que termine")
)

// Nuevo carga el JSON (si existe) y deja el orquestador listo.
func Nuevo(cfg Config, ej Ejecutor) (*Orquestador, error) {
	for _, dir := range []string{filepath.Dir(cfg.ArchivoDatos), cfg.DirSubidas} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return nil, err
		}
	}
	o := &Orquestador{cfg: cfg, ej: ej, instancias: map[string]*Instancia{}}
	if err := o.cargar(); err != nil {
		return nil, err
	}
	// Si la app se cerró en medio de una operación, ese estado ya no es real.
	for _, i := range o.instancias {
		switch i.Estado {
		case Creando:
			i.Estado, i.Mensaje = ConError, "la creación se interrumpió por un reinicio de la aplicación; elimine la instancia y créela de nuevo"
		case Publicando:
			i.Estado, i.Mensaje = Lista, "la publicación se interrumpió por un reinicio de la aplicación; vuelva a publicar"
			if i.Publicada != nil {
				i.Estado = Publicada
			}
		case Eliminando:
			i.Estado, i.Mensaje = ConError, "la eliminación se interrumpió por un reinicio de la aplicación; intente eliminar de nuevo"
		}
	}
	return o, o.guardar()
}

// Modo devuelve "simulado" o "real".
func (o *Orquestador) Modo() string { return o.cfg.Modo }

// Dominio devuelve el dominio de la zona (cloud.local).
func (o *Orquestador) Dominio() string { return o.cfg.Dominio }

// ---------- Persistencia ----------

func (o *Orquestador) cargar() error {
	datos, err := os.ReadFile(o.cfg.ArchivoDatos)
	if errors.Is(err, os.ErrNotExist) {
		return nil // primera ejecución
	}
	if err != nil {
		return err
	}
	var lista []*Instancia
	if err := json.Unmarshal(datos, &lista); err != nil {
		return fmt.Errorf("el archivo %s está dañado: %v", o.cfg.ArchivoDatos, err)
	}
	for _, i := range lista {
		o.instancias[i.Nombre] = i
	}
	log.Printf("cargadas %d instancias de %s", len(lista), o.cfg.ArchivoDatos)
	return nil
}

// guardar escribe primero un archivo temporal y luego lo renombra, para que un
// cierre inesperado nunca deje el JSON a medias. Se llama con o.mu tomado.
func (o *Orquestador) guardar() error {
	datos, err := json.MarshalIndent(o.listaOrdenada(), "", "  ")
	if err != nil {
		return err
	}
	temporal := o.cfg.ArchivoDatos + ".tmp"
	if err := os.WriteFile(temporal, datos, 0o644); err != nil {
		return err
	}
	return os.Rename(temporal, o.cfg.ArchivoDatos)
}

func (o *Orquestador) listaOrdenada() []Instancia {
	lista := make([]Instancia, 0, len(o.instancias))
	for _, i := range o.instancias {
		lista = append(lista, *i)
	}
	sort.Slice(lista, func(a, b int) bool { return lista[a].Creada.Before(lista[b].Creada) })
	return lista
}

// actualizar aplica un cambio a una instancia y guarda.
func (o *Orquestador) actualizar(nombre string, cambio func(*Instancia)) {
	o.mu.Lock()
	defer o.mu.Unlock()
	if i, ok := o.instancias[nombre]; ok {
		cambio(i)
		if err := o.guardar(); err != nil {
			log.Printf("error guardando %s: %v", o.cfg.ArchivoDatos, err)
		}
	}
}

// ---------- Consultas ----------

// Listar devuelve las instancias ordenadas por fecha de creación.
func (o *Orquestador) Listar() []Instancia {
	o.mu.Lock()
	defer o.mu.Unlock()
	return o.listaOrdenada()
}

func (o *Orquestador) url(nombre string) string {
	if o.cfg.Modo == "simulado" {
		return "/sim/" + nombre + "/"
	}
	return fmt.Sprintf("http://%s.%s", nombre, o.cfg.Dominio)
}

// siguienteIP busca la primera IP libre del rango. Se llama con o.mu tomado.
// Las instancias con error conservan su IP hasta que se eliminen.
func (o *Orquestador) siguienteIP() string {
	usadas := map[string]bool{}
	for _, i := range o.instancias {
		usadas[i.IP] = true
	}
	for n := o.cfg.PrimeraIP; n <= o.cfg.UltimaIP; n++ {
		ip := fmt.Sprintf("%s.%d", o.cfg.Red, n)
		if !usadas[ip] {
			return ip
		}
	}
	return ""
}

// ValidarNombre normaliza el nombre y explica por qué no es válido.
func ValidarNombre(nombre string) (string, error) {
	nombre = strings.ToLower(strings.TrimSpace(nombre))
	switch {
	case nombre == "":
		return "", errors.New("escriba el nombre del host")
	case len(nombre) > 63:
		return "", errors.New("el nombre no puede tener más de 63 caracteres")
	case !reHostname.MatchString(nombre):
		return "", errors.New("nombre no válido: use letras minúsculas, números y guiones; debe empezar por letra y no terminar en guion")
	case reservados[nombre]:
		return "", fmt.Errorf("el nombre %q está reservado", nombre)
	}
	return nombre, nil
}

// ---------- Operaciones (Aceptar, Publicar, Eliminar) ----------

// Aceptar registra la solicitud y lanza la creación en segundo plano.
// Responde de inmediato con la instancia en estado "creando".
func (o *Orquestador) Aceptar(nombre string) (Instancia, error) {
	nombre, err := ValidarNombre(nombre)
	if err != nil {
		return Instancia{}, err
	}
	o.mu.Lock()
	if _, existe := o.instancias[nombre]; existe {
		o.mu.Unlock()
		return Instancia{}, fmt.Errorf("ya existe una instancia llamada %s", nombre)
	}
	ip := o.siguienteIP()
	if ip == "" {
		o.mu.Unlock()
		return Instancia{}, errors.New("no hay direcciones IP libres en el rango")
	}
	inst := &Instancia{Nombre: nombre, IP: ip, Estado: Creando, Creada: time.Now(), URL: o.url(nombre)}
	o.instancias[nombre] = inst
	err = o.guardar()
	copia := *inst
	o.mu.Unlock()
	if err != nil {
		return copia, err
	}
	log.Printf("solicitud: crear %s con IP %s", nombre, ip)
	go o.crear(nombre, ip)
	return copia, nil
}

func (o *Orquestador) crear(nombre, ip string) {
	o.cola.Lock()
	defer o.cola.Unlock()

	if salida, err := o.ej.CrearInstancia(nombre, ip); err != nil {
		o.fallo(nombre, ConError, "crear-instancia", err, salida)
		return
	}
	if salida, err := o.ej.RegistrarDNS(nombre, ip); err != nil {
		o.fallo(nombre, ConError, "registrar-dns", err, salida)
		return
	}
	o.actualizar(nombre, func(i *Instancia) { i.Estado, i.Mensaje = Lista, "" })
	log.Printf("instancia %s lista", nombre)
}

// Publicar guarda el .zip, lo valida y lanza el despliegue en segundo plano.
func (o *Orquestador) Publicar(nombre, nombreArchivo string, contenido io.Reader) (Instancia, error) {
	nombre = strings.ToLower(strings.TrimSpace(nombre))
	o.mu.Lock()
	inst, ok := o.instancias[nombre]
	if !ok {
		o.mu.Unlock()
		return Instancia{}, fmt.Errorf("no existe la instancia %q: primero créela con Aceptar", nombre)
	}
	if inst.Estado != Lista && inst.Estado != Publicada {
		estado := inst.Estado
		o.mu.Unlock()
		return Instancia{}, fmt.Errorf("la instancia no está lista para publicar (estado: %s)", estado)
	}
	o.mu.Unlock()

	// Guardar el .zip con un nombre fijo por instancia (el del usuario no se usa como ruta).
	ruta := filepath.Join(o.cfg.DirSubidas, nombre+".zip")
	if err := guardarArchivo(ruta, contenido); err != nil {
		return Instancia{}, fmt.Errorf("no se pudo guardar el archivo: %v", err)
	}
	archivos, tieneIndex, err := ValidarZip(ruta)
	if err != nil {
		os.Remove(ruta)
		return Instancia{}, err
	}
	aviso := ""
	if !tieneIndex {
		aviso = "aviso: el .zip no tiene index.html; Apache mostrará el listado de archivos o un error"
	}
	rutaAbs, _ := filepath.Abs(ruta)

	o.mu.Lock()
	inst, ok = o.instancias[nombre]
	if !ok || (inst.Estado != Lista && inst.Estado != Publicada) {
		o.mu.Unlock()
		return Instancia{}, ErrOcupada
	}
	anterior := inst.Estado
	inst.Estado, inst.Mensaje = Publicando, aviso
	o.guardar()
	copia := *inst
	o.mu.Unlock()

	log.Printf("solicitud: publicar %s (%s, %d archivos) en %s", nombreArchivo, ruta, archivos, nombre)
	go o.desplegar(nombre, rutaAbs, filepath.Base(nombreArchivo), anterior, aviso)
	return copia, nil
}

func (o *Orquestador) desplegar(nombre, rutaZip, nombreArchivo string, anterior Estado, aviso string) {
	o.cola.Lock()
	defer o.cola.Unlock()

	if salida, err := o.ej.Desplegar(nombre, rutaZip); err != nil {
		// La VM sigue bien: vuelve a su estado anterior con el mensaje de error.
		o.fallo(nombre, anterior, "desplegar", err, salida)
		return
	}
	ahora := time.Now()
	o.actualizar(nombre, func(i *Instancia) {
		i.Estado, i.Mensaje, i.Publicada, i.Archivo = Publicada, aviso, &ahora, nombreArchivo
	})
	log.Printf("instancia %s publicada con %s", nombre, nombreArchivo)
}

// Eliminar lanza el borrado de la VM y del registro DNS en segundo plano.
func (o *Orquestador) Eliminar(nombre string) (Instancia, error) {
	nombre = strings.ToLower(strings.TrimSpace(nombre))
	o.mu.Lock()
	inst, ok := o.instancias[nombre]
	if !ok {
		o.mu.Unlock()
		return Instancia{}, ErrNoExiste
	}
	if inst.Estado == Creando || inst.Estado == Publicando || inst.Estado == Eliminando {
		o.mu.Unlock()
		return Instancia{}, ErrOcupada
	}
	inst.Estado, inst.Mensaje = Eliminando, ""
	o.guardar()
	copia := *inst
	o.mu.Unlock()

	log.Printf("solicitud: eliminar %s", nombre)
	go o.eliminar(nombre)
	return copia, nil
}

func (o *Orquestador) eliminar(nombre string) {
	o.cola.Lock()
	defer o.cola.Unlock()

	if salida, err := o.ej.Eliminar(nombre); err != nil {
		o.fallo(nombre, ConError, "eliminar", err, salida)
		return
	}
	o.mu.Lock()
	delete(o.instancias, nombre)
	o.guardar()
	o.mu.Unlock()
	os.Remove(filepath.Join(o.cfg.DirSubidas, nombre+".zip"))
	log.Printf("instancia %s eliminada", nombre)
}

// fallo deja la instancia en el estado indicado con un mensaje legible.
func (o *Orquestador) fallo(nombre string, estado Estado, operacion string, err error, salida string) {
	mensaje := fmt.Sprintf("falló %s: %v", operacion, err)
	if s := ultimasLineas(salida, 3); s != "" {
		mensaje += " | " + s
	}
	log.Printf("instancia %s: %s", nombre, mensaje)
	o.actualizar(nombre, func(i *Instancia) { i.Estado, i.Mensaje = estado, mensaje })
}

func ultimasLineas(texto string, n int) string {
	lineas := strings.Split(strings.TrimSpace(strings.ReplaceAll(texto, "\r", "")), "\n")
	if len(lineas) > n {
		lineas = lineas[len(lineas)-n:]
	}
	resultado := strings.TrimSpace(strings.Join(lineas, " / "))
	if len(resultado) > 400 {
		resultado = resultado[:400] + "..."
	}
	return resultado
}

func guardarArchivo(ruta string, contenido io.Reader) error {
	f, err := os.Create(ruta)
	if err != nil {
		return err
	}
	if _, err := io.Copy(f, contenido); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}
