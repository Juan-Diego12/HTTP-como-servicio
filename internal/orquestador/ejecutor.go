package orquestador

// Ejecutor es el contrato con la parte de infraestructura (scripts de Daniel).
// Cada método devuelve la salida del script, útil para mostrar o registrar errores.
type Ejecutor interface {
	CrearInstancia(nombre, ip string) (string, error) // crea la VM desde ApacheServer.vdi, ajusta hostname e IP y la arranca
	RegistrarDNS(nombre, ip string) (string, error)   // agrega el registro A en la zona
	Desplegar(nombre, rutaZip string) (string, error) // copia y descomprime el .zip y recarga Apache
	Eliminar(nombre string) (string, error)           // apaga y borra la VM y quita el registro DNS
}
