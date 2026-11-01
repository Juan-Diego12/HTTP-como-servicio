package orquestador

import "time"

// Estado del ciclo de vida de una instancia.
type Estado string

const (
	Creando    Estado = "creando"    // creando la VM y registrando el DNS
	Lista      Estado = "lista"      // VM y DNS listos, sin contenido publicado
	Publicando Estado = "publicando" // desplegando el .zip
	Publicada  Estado = "publicada"  // contenido del usuario en línea
	Eliminando Estado = "eliminando" // apagando y borrando la VM y su registro DNS
	ConError   Estado = "error"      // falló la creación o la eliminación
)

// Instancia es cada servidor Apache aprovisionado. Es lo que se guarda en el JSON
// y lo que muestra el dashboard.
type Instancia struct {
	Nombre    string     `json:"nombre"`              // hostname y nombre de la VM
	IP        string     `json:"ip"`                  // por ejemplo 192.168.10.30
	Estado    Estado     `json:"estado"`
	Mensaje   string     `json:"mensaje,omitempty"`   // último error o aviso
	Creada    time.Time  `json:"creada"`
	Publicada *time.Time `json:"publicada,omitempty"` // fecha de la última publicación
	Archivo   string     `json:"archivo,omitempty"`   // nombre del .zip publicado
	URL       string     `json:"url"`                 // enlace para abrir la página
}
