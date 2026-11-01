// HTTPaaS: aplicación web de gestión que aprovisiona instancias de Apache en VirtualBox,
// las registra en el DNS (Bind9) y publica en ellas el contenido .zip del usuario.
package main

import (
	"log"
	"net/http"
	"os"
	"strings"

	"httpaas/internal/orquestador"
	"httpaas/internal/web"
)

func env(clave, porDefecto string) string {
	if v := os.Getenv(clave); v != "" {
		return v
	}
	return porDefecto
}

func main() {
	modo := strings.ToLower(env("MODO", "simulado"))
	dirSitiosSimulados := "simulado/sitios"

	var ejecutor orquestador.Ejecutor
	if modo == "real" {
		// Llama a los scripts de Daniel: crear-instancia, registrar-dns, desplegar y eliminar.
		ejecutor = orquestador.NuevoEjecutorScripts(env("SCRIPTS_DIR", "scripts"), env("SCRIPTS_EXT", ".ps1"))
	} else {
		// Simula las 4 operaciones sin VirtualBox; el contenido se publica en /sim/<nombre>/.
		modo = "simulado"
		ejecutor = orquestador.NuevoEjecutorSimulado(dirSitiosSimulados)
	}

	orq, err := orquestador.Nuevo(orquestador.Config{
		ArchivoDatos: env("DATA_FILE", "data/instancias.json"),
		DirSubidas:   "uploads",
		Dominio:      env("DOMINIO", "cloud.local"),
		Red:          env("RED", "192.168.10"), // las instancias usan <Red>.30 en adelante
		PrimeraIP:    30,
		UltimaIP:     254,
		Modo:         modo,
	}, ejecutor)
	if err != nil {
		log.Fatal("no se pudo iniciar el orquestador: ", err)
	}

	mux := http.NewServeMux()
	web.Registrar(mux, orq)
	if modo == "simulado" {
		os.MkdirAll(dirSitiosSimulados, 0o755)
		mux.Handle("/sim/", http.StripPrefix("/sim/", http.FileServer(http.Dir(dirSitiosSimulados))))
	}

	direccion := env("DIRECCION", "127.0.0.1") + ":" + env("PORT", "8080")
	log.Printf("HTTPaaS en modo %s: http://%s", modo, direccion)
	log.Fatal(http.ListenAndServe(direccion, mux))
}
