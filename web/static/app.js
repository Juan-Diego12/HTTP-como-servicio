// Dashboard: envía las solicitudes a la API y refresca la lista cada 2 segundos.
const $ = (id) => document.getElementById(id);
let dominio = "cloud.local";

const textoEstado = {
  creando: "Creando", lista: "Lista", publicando: "Publicando",
  publicada: "Publicada", eliminando: "Eliminando", error: "Error",
};

function avisar(texto, esError = false) {
  const aviso = $("aviso");
  aviso.textContent = texto;
  aviso.className = "aviso" + (esError ? " error" : "");
  aviso.hidden = false;
}

function fecha(iso) {
  const d = new Date(iso);
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

async function pedir(url, opciones) {
  const r = await fetch(url, opciones);
  let datos = {};
  try { datos = await r.json(); } catch { datos = { mensaje: `error HTTP ${r.status}` }; }
  return datos;
}

function fila(i) {
  const tr = document.createElement("tr");
  const enLinea = i.estado === "lista" || i.estado === "publicada";
  const enlace = enLinea
    ? `<a href="${i.url}" target="_blank" rel="noopener">${i.url.startsWith("/sim/") ? `http://${i.nombre}.${dominio}` : i.url}</a>`
    : `<span>http://${i.nombre}.${dominio}</span>`;
  const ocupada = ["creando", "publicando", "eliminando"].includes(i.estado);
  const esAviso = i.mensaje && i.mensaje.startsWith("aviso");
  tr.innerHTML = `
    <td>${enlace}${i.mensaje ? `<span class="mensaje${esAviso ? " info" : ""}"></span>` : ""}</td>
    <td class="ip">${i.ip}/24</td>
    <td><button type="button" class="enlace-host" title="Usar este host en el formulario"></button></td>
    <td class="fecha">${fecha(i.creada)}</td>
    <td><span class="estado ${i.estado}">${textoEstado[i.estado] || i.estado}</span></td>
    <td><button type="button" class="btn-eliminar" ${ocupada ? "disabled" : ""}>Eliminar</button></td>`;
  if (i.mensaje) tr.querySelector(".mensaje").textContent = i.mensaje; // texto, nunca HTML
  const host = tr.querySelector(".enlace-host");
  host.textContent = i.nombre;
  host.style.cssText = "background:none;border:0;padding:0;color:inherit;text-decoration:underline dotted;cursor:pointer";
  host.onclick = () => { $("nombre").value = i.nombre; actualizarVista(); $("zip").focus(); };
  tr.querySelector(".btn-eliminar").onclick = () => eliminar(i.nombre);
  return tr;
}

async function refrescar() {
  try {
    const datos = await pedir("/api/instancias");
    const lista = datos.instancias || [];
    const cuerpo = $("lista");
    cuerpo.replaceChildren(...lista.map(fila));
    $("vacio").hidden = lista.length > 0;
  } catch {
    avisar("No hay conexión con la aplicación de gestión. Verifique que siga en ejecución.", true);
  }
}

async function aceptar() {
  const nombre = $("nombre").value.trim().toLowerCase();
  if (!nombre) return avisar("Escriba el nombre del host.", true);
  $("aceptar").disabled = true;
  try {
    const datos = await pedir("/api/instancias", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ nombre }),
    });
    avisar(datos.mensaje, !datos.exito);
    refrescar();
  } finally {
    $("aceptar").disabled = false;
  }
}

async function publicar() {
  const nombre = $("nombre").value.trim().toLowerCase();
  const archivo = $("zip").files[0];
  if (!nombre) return avisar("Escriba el nombre del host donde se publicará el contenido.", true);
  if (!archivo) return avisar("Seleccione el archivo .zip con el contenido web.", true);
  const formulario = new FormData();
  formulario.append("zip", archivo);
  $("publicar").disabled = true;
  try {
    const datos = await pedir(`/api/instancias/${encodeURIComponent(nombre)}/publicar`, { method: "POST", body: formulario });
    avisar(datos.mensaje, !datos.exito);
    if (datos.exito) $("zip").value = "";
    refrescar();
  } finally {
    $("publicar").disabled = false;
  }
}

async function eliminar(nombre) {
  if (!confirm(`¿Eliminar ${nombre}? Se apagará y borrará su máquina virtual y su registro DNS.`)) return;
  const datos = await pedir(`/api/instancias/${encodeURIComponent(nombre)}`, { method: "DELETE" });
  avisar(datos.mensaje, !datos.exito);
  refrescar();
}

function actualizarVista() {
  const nombre = $("nombre").value.trim().toLowerCase() || "nombre";
  $("vista-url").textContent = `http://${nombre}.${dominio}`;
}

async function iniciar() {
  const datos = await pedir("/api/config");
  if (datos.config) {
    dominio = datos.config.dominio;
    if (datos.config.modo === "simulado") {
      $("modo").textContent = "Modo simulado: no se crean máquinas virtuales";
      $("modo").hidden = false;
    }
  }
  actualizarVista();
  $("aceptar").onclick = aceptar;
  $("publicar").onclick = publicar;
  $("nombre").oninput = actualizarVista;
  $("nombre").onkeydown = (e) => { if (e.key === "Enter") aceptar(); };
  refrescar();
  setInterval(refrescar, 2000);
}

iniciar();
