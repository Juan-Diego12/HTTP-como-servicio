package orquestador

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// EjecutorScripts llama a los scripts del contrato con exec.Command.
// Nombres esperados en la carpeta de scripts: crear-instancia, registrar-dns, desplegar y eliminar.
type EjecutorScripts struct {
	Dir        string
	Extension  string // ".ps1" o ".bat"
	Interprete string
	Prefijo    []string // argumentos del intérprete antes de la ruta del script
	Tiempo     time.Duration
}

// NuevoEjecutorScripts prepara el intérprete según la extensión de los scripts.
// tiempo es el máximo por script; crear-instancia puede tardar varios minutos
// (arranque de la VM, configuración y verificación por HTTP).
func NuevoEjecutorScripts(dir, extension string, tiempo time.Duration) *EjecutorScripts {
	if tiempo <= 0 {
		tiempo = 25 * time.Minute
	}
	e := &EjecutorScripts{Dir: dir, Extension: extension, Tiempo: tiempo}
	if extension == ".bat" || extension == ".cmd" {
		e.Interprete, e.Prefijo = "cmd", []string{"/c"}
	} else {
		e.Extension = ".ps1"
		e.Interprete, e.Prefijo = "powershell", []string{"-NoProfile", "-ExecutionPolicy", "Bypass", "-File"}
	}
	return e
}

func (e *EjecutorScripts) correr(script string, args ...string) (string, error) {
	ruta, err := filepath.Abs(filepath.Join(e.Dir, script+e.Extension))
	if err != nil {
		return "", err
	}
	if _, err := os.Stat(ruta); err != nil {
		return "", fmt.Errorf("no se encontró el script %s", ruta)
	}
	ctx, cancelar := context.WithTimeout(context.Background(), e.Tiempo)
	defer cancelar()

	todos := append(append([]string{}, e.Prefijo...), ruta)
	todos = append(todos, args...)
	inicio := time.Now()
	salida, err := exec.CommandContext(ctx, e.Interprete, todos...).CombinedOutput()
	texto := strings.TrimSpace(string(salida))

	estado := "OK"
	if err != nil {
		estado = "ERROR"
	}
	log.Printf("[script] %s %s %v (%s)", estado, script, args, time.Since(inicio).Round(time.Millisecond))

	if ctx.Err() == context.DeadlineExceeded {
		return texto, fmt.Errorf("%s superó el tiempo máximo de %s", script, e.Tiempo)
	}
	if err != nil {
		return texto, fmt.Errorf("%s terminó con error (%v)", script, err)
	}
	return texto, nil
}

func (e *EjecutorScripts) CrearInstancia(nombre, ip string) (string, error) {
	return e.correr("crear-instancia", nombre, ip)
}

func (e *EjecutorScripts) RegistrarDNS(nombre, ip string) (string, error) {
	return e.correr("registrar-dns", nombre, ip)
}

func (e *EjecutorScripts) Desplegar(nombre, rutaZip string) (string, error) {
	return e.correr("desplegar", nombre, rutaZip)
}

func (e *EjecutorScripts) Eliminar(nombre string) (string, error) {
	return e.correr("eliminar", nombre)
}
