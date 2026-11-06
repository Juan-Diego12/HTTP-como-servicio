package orquestador

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"runtime"
	"strings"
	"time"
)

// RutaVBoxManage devuelve el ejecutable de VBoxManage: la variable VBOXMANAGE, el que esté
// en el PATH o el de la instalación predeterminada.
func RutaVBoxManage() string {
	if v := os.Getenv("VBOXMANAGE"); v != "" {
		return v
	}
	if ruta, err := exec.LookPath("VBoxManage"); err == nil {
		return ruta
	}
	return `C:\Program Files\Oracle\VirtualBox\VBoxManage.exe`
}

var reVM = regexp.MustCompile(`^"(.+)" \{[0-9a-fA-F-]+\}$`)

// ListarVMs devuelve los nombres de todas las VMs registradas en VirtualBox.
func ListarVMs(vboxmanage string) ([]string, error) {
	ctx, cancelar := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancelar()
	salida, err := exec.CommandContext(ctx, vboxmanage, "list", "vms").Output()
	if err != nil {
		return nil, fmt.Errorf("no se pudo consultar VirtualBox (%s list vms): %v", vboxmanage, err)
	}
	var nombres []string
	lector := bufio.NewScanner(strings.NewReader(string(salida)))
	for lector.Scan() {
		if m := reVM.FindStringSubmatch(strings.TrimSpace(lector.Text())); m != nil {
			nombres = append(nombres, m[1])
		}
	}
	return nombres, nil
}

// buscarVM devuelve el nombre de la VM que coincide sin distinguir mayúsculas
// (en Windows, "np2-base" y "NP2-Base" usarían la misma carpeta).
func buscarVM(nombres []string, nombre string) (string, bool) {
	for _, n := range nombres {
		if strings.EqualFold(n, nombre) {
			return n, true
		}
	}
	return "", false
}

// IPResponde indica si algún equipo responde ping en esa IP.
// En Windows, ping puede terminar con código 0 aunque el destino no sea accesible,
// por eso se busca "TTL=" en la salida (aparece igual en español y en inglés).
func IPResponde(ip string) bool {
	args := []string{"-c", "1", "-W", "1", ip}
	if runtime.GOOS == "windows" {
		args = []string{"-n", "1", "-w", "800", ip}
	}
	ctx, cancelar := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancelar()
	salida, _ := exec.CommandContext(ctx, "ping", args...).CombinedOutput()
	return strings.Contains(strings.ToUpper(string(salida)), "TTL=")
}
