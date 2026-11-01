// Package web expone la API JSON que usa el dashboard y sirve la interfaz.
package web

import (
	"encoding/json"
	"errors"
	"net/http"
	"path/filepath"
	"strings"

	"httpaas/internal/orquestador"
)

// Tamaño máximo del .zip.
const maxZip = 50 << 20 // 50 MB

type respuesta struct {
	Exito      bool                    `json:"exito"`
	Mensaje    string                  `json:"mensaje"`
	Instancia  *orquestador.Instancia  `json:"instancia,omitempty"`
	Instancias []orquestador.Instancia `json:"instancias"`
	Config     map[string]string       `json:"config,omitempty"`
}

func responder(w http.ResponseWriter, estado int, r respuesta) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(estado)
	json.NewEncoder(w).Encode(r)
}

// Registrar agrega las rutas al mux.
func Registrar(mux *http.ServeMux, o *orquestador.Orquestador) {
	h := &manejador{o: o}
	mux.HandleFunc("GET /api/config", h.config)
	mux.HandleFunc("GET /api/instancias", h.listar)
	mux.HandleFunc("POST /api/instancias", h.aceptar)
	mux.HandleFunc("POST /api/instancias/{nombre}/publicar", h.publicar)
	mux.HandleFunc("DELETE /api/instancias/{nombre}", h.eliminar)
	mux.Handle("/", http.FileServer(http.Dir("web/static")))
}

type manejador struct{ o *orquestador.Orquestador }

// GET /api/config
func (h *manejador) config(w http.ResponseWriter, r *http.Request) {
	responder(w, http.StatusOK, respuesta{Exito: true,
		Config: map[string]string{"modo": h.o.Modo(), "dominio": h.o.Dominio()}})
}

// GET /api/instancias
func (h *manejador) listar(w http.ResponseWriter, r *http.Request) {
	lista := h.o.Listar()
	if lista == nil {
		lista = []orquestador.Instancia{}
	}
	responder(w, http.StatusOK, respuesta{Exito: true, Instancias: lista})
}

// POST /api/instancias   JSON: {"nombre": "paisajes"}
func (h *manejador) aceptar(w http.ResponseWriter, r *http.Request) {
	var e struct {
		Nombre string `json:"nombre"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&e); err != nil {
		responder(w, http.StatusBadRequest, respuesta{Mensaje: "datos inválidos"})
		return
	}
	inst, err := h.o.Aceptar(e.Nombre)
	if err != nil {
		responder(w, http.StatusBadRequest, respuesta{Mensaje: err.Error()})
		return
	}
	responder(w, http.StatusAccepted, respuesta{Exito: true, Instancia: &inst,
		Mensaje: "solicitud recibida: creando " + inst.Nombre + " con IP " + inst.IP})
}

// POST /api/instancias/{nombre}/publicar   multipart/form-data, campo "zip"
func (h *manejador) publicar(w http.ResponseWriter, r *http.Request) {
	nombre := r.PathValue("nombre")
	r.Body = http.MaxBytesReader(w, r.Body, maxZip+(1<<20))
	if err := r.ParseMultipartForm(32 << 20); err != nil {
		responder(w, http.StatusBadRequest, respuesta{Mensaje: "no se pudo leer el archivo (máximo 50 MB)"})
		return
	}
	archivo, cabecera, err := r.FormFile("zip")
	if err != nil {
		responder(w, http.StatusBadRequest, respuesta{Mensaje: "seleccione un archivo .zip"})
		return
	}
	defer archivo.Close()
	if !strings.EqualFold(filepath.Ext(cabecera.Filename), ".zip") {
		responder(w, http.StatusBadRequest, respuesta{Mensaje: "el contenido debe ser un archivo .zip"})
		return
	}
	inst, err := h.o.Publicar(nombre, cabecera.Filename, archivo)
	if err != nil {
		responder(w, http.StatusBadRequest, respuesta{Mensaje: err.Error()})
		return
	}
	mensaje := "publicando " + cabecera.Filename + " en " + inst.Nombre
	if inst.Mensaje != "" {
		mensaje += " (" + inst.Mensaje + ")"
	}
	responder(w, http.StatusAccepted, respuesta{Exito: true, Instancia: &inst, Mensaje: mensaje})
}

// DELETE /api/instancias/{nombre}
func (h *manejador) eliminar(w http.ResponseWriter, r *http.Request) {
	inst, err := h.o.Eliminar(r.PathValue("nombre"))
	if err != nil {
		estado := http.StatusBadRequest
		if errors.Is(err, orquestador.ErrNoExiste) {
			estado = http.StatusNotFound
		}
		responder(w, estado, respuesta{Mensaje: err.Error()})
		return
	}
	responder(w, http.StatusAccepted, respuesta{Exito: true, Instancia: &inst,
		Mensaje: "eliminando " + inst.Nombre})
}
