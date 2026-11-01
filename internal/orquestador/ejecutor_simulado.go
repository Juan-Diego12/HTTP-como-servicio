package orquestador

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// EjecutorSimulado reemplaza los scripts para desarrollar sin VMs.
// Tarda un poco en cada operación (para ver los estados en el dashboard) y publica
// el contenido en una carpeta local que la app sirve en /sim/<nombre>/.
//
// Para probar el manejo de errores, use nombres que contengan:
//
//	fallacrear, falladns, fallapub o fallaelim
type EjecutorSimulado struct {
	DirSitios string
	Demora    time.Duration
}

func NuevoEjecutorSimulado(dirSitios string) *EjecutorSimulado {
	return &EjecutorSimulado{DirSitios: dirSitios, Demora: 2 * time.Second}
}

func (s *EjecutorSimulado) esperar(nombre, clave, operacion string) error {
	time.Sleep(s.Demora)
	if strings.Contains(nombre, clave) {
		return fmt.Errorf("fallo simulado en %s", operacion)
	}
	return nil
}

func (s *EjecutorSimulado) CrearInstancia(nombre, ip string) (string, error) {
	if err := s.esperar(nombre, "fallacrear", "crear-instancia"); err != nil {
		return "VBoxManage: error simulado", err
	}
	return fmt.Sprintf("[simulado] VM %s creada con IP %s", nombre, ip), nil
}

func (s *EjecutorSimulado) RegistrarDNS(nombre, ip string) (string, error) {
	if err := s.esperar(nombre, "falladns", "registrar-dns"); err != nil {
		return "nsupdate: error simulado", err
	}
	return fmt.Sprintf("[simulado] registro A %s -> %s", nombre, ip), nil
}

func (s *EjecutorSimulado) Desplegar(nombre, rutaZip string) (string, error) {
	if err := s.esperar(nombre, "fallapub", "desplegar"); err != nil {
		return "", err
	}
	destino := filepath.Join(s.DirSitios, nombre)
	if err := os.RemoveAll(destino); err != nil {
		return "", err
	}
	if err := Extraer(rutaZip, destino); err != nil {
		return "", fmt.Errorf("no se pudo descomprimir: %v", err)
	}
	return "[simulado] contenido publicado en " + destino, nil
}

func (s *EjecutorSimulado) Eliminar(nombre string) (string, error) {
	if err := s.esperar(nombre, "fallaelim", "eliminar"); err != nil {
		return "", err
	}
	os.RemoveAll(filepath.Join(s.DirSitios, nombre))
	return "[simulado] VM y registro DNS de " + nombre + " eliminados", nil
}
