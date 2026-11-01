package orquestador

import (
	"archive/zip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// rutaSegura evita "zip slip": rutas absolutas, con unidad (C:) o que suban con "..".
func rutaSegura(nombre string) bool {
	n := strings.ReplaceAll(nombre, "\\", "/")
	if strings.HasPrefix(n, "/") || strings.Contains(n, ":") {
		return false
	}
	for _, parte := range strings.Split(n, "/") {
		if parte == ".." {
			return false
		}
	}
	return true
}

// ValidarZip comprueba que el archivo sea un .zip válido, con archivos y sin rutas peligrosas.
// Devuelve cuántos archivos tiene y si incluye un index.html.
func ValidarZip(ruta string) (archivos int, tieneIndex bool, err error) {
	r, err := zip.OpenReader(ruta)
	if err != nil {
		return 0, false, fmt.Errorf("el archivo no es un .zip válido")
	}
	defer r.Close()
	for _, f := range r.File {
		if !rutaSegura(f.Name) {
			return 0, false, fmt.Errorf("el .zip contiene una ruta no permitida: %s", f.Name)
		}
		if f.FileInfo().IsDir() {
			continue
		}
		archivos++
		if strings.EqualFold(filepath.Base(f.Name), "index.html") {
			tieneIndex = true
		}
	}
	if archivos == 0 {
		return 0, false, fmt.Errorf("el .zip está vacío")
	}
	return archivos, tieneIndex, nil
}

// prefijoComun devuelve "carpeta/" si todo el contenido está dentro de una sola carpeta
// (pasa cuando se comprime la carpeta en vez de su contenido).
func prefijoComun(archivos []*zip.File) string {
	prefijo := ""
	for _, f := range archivos {
		n := strings.ReplaceAll(f.Name, "\\", "/")
		i := strings.Index(n, "/")
		if i < 0 {
			return "" // hay archivos en la raíz
		}
		if prefijo == "" {
			prefijo = n[:i+1]
		} else if n[:i+1] != prefijo {
			return ""
		}
	}
	return prefijo
}

// Extraer descomprime el .zip en destino (solo se usa en modo simulado).
func Extraer(rutaZip, destino string) error {
	r, err := zip.OpenReader(rutaZip)
	if err != nil {
		return err
	}
	defer r.Close()
	prefijo := prefijoComun(r.File)
	for _, f := range r.File {
		nombre := strings.TrimPrefix(strings.ReplaceAll(f.Name, "\\", "/"), prefijo)
		if nombre == "" || !rutaSegura(nombre) {
			continue
		}
		ruta := filepath.Join(destino, filepath.FromSlash(nombre))
		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(ruta, 0o755); err != nil {
				return err
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(ruta), 0o755); err != nil {
			return err
		}
		if err := copiarDelZip(f, ruta); err != nil {
			return err
		}
	}
	return nil
}

func copiarDelZip(f *zip.File, ruta string) error {
	origen, err := f.Open()
	if err != nil {
		return err
	}
	defer origen.Close()
	destino, err := os.Create(ruta)
	if err != nil {
		return err
	}
	defer destino.Close()
	_, err = io.Copy(destino, origen)
	return err
}
