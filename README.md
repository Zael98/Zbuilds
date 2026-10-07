# Zbuilds

Addon de **WoW Forever** que reúne builds de talentos de varias webs y te deja verlas, compararlas y aprenderlas en el juego.

- **Fuentes:** builds populares de [Talents Forever](https://talentsforever.com) (datos CC BY 4.0) y las guías de [Icy Veins](https://www.icy-veins.com/wow-forever/), [Warcraft Tavern](https://www.warcrafttavern.com/forever/guides/), [Method](https://www.method.gg/wow-forever) y [WoW Forever Builds](https://wowforeverbuilds.com), más las guías extra de `tools/links.txt`.
- **Siempre válidas:** cada build se traduce al árbol actual del juego por el nombre de sus talentos, y se descarta si usa un talento que ya no existe o no se puede aprender (por ejemplo, si un talento ha cambiado de fila).
- **Pestañas por especialización:** se abre en la tuya. Puedes filtrar por tipo (Leveo, PvE, PvP), por web y con un buscador.
- **Árboles:** muestran los rangos de la build y, con el color del borde, lo que ya tienes aprendido. Incluyen las flechas de requisitos.
- **Orden de puntos:** una línea de tiempo con los 51 puntos en orden y su nivel; pulsa uno para ver la build tal como queda en ese nivel.
- **Comparar:** clic derecho en otra build, o "Comparar con mis talentos". Cada talento muestra los rangos de A y B, y debajo aparece la lista de diferencias.
- **Aprender puntos libres:** gasta tus puntos siguiendo el orden de la build (fuera de combate).
- **+ Importar enlace:** pega un enlace de build de talentsforever.com, Icy Veins, Warcraft Tavern o wowforeverbuilds.com. Funciona sin conexión y se guarda en tu cuenta.
- **Recomendaciones:** las builds iguales de varias webs se juntan en una ("también la recomiendan: …") y salen primero.
- **Builds de la beta:** marcadas, y se pueden ocultar con el filtro "Beta".
- **Nombres y descripciones en tu idioma** para los talentos de todas las clases.
- **Accesos:** botón en el minimapa (`/zb minimap` lo oculta), menú de addons del juego y botón sobre la ventana de talentos.

Comandos: `/zb` abre la ventana · `/zb minimap` oculta o muestra el botón del minimapa · `/zb diag` comprueba qué permite este cliente

Idiomas: inglés, español, alemán, francés, portugués, italiano, ruso, coreano y chino (simplificado y tradicional). Se elige el del juego automáticamente.

## Instalación

- **CurseForge / WowUp:** instala "Zbuilds"; tu gestor de addons te avisará de cada actualización.
- **A mano:** descarga el `.zip` de la última [versión](../../releases) y descomprímelo en `World of Warcraft\<cliente>\Interface\AddOns\`.

## Cómo se actualizan las builds

Los addons de WoW no pueden conectarse a internet, así que el trabajo lo hace GitHub: cada día ejecuta `tools/update_builds.py`. Si alguna build ha cambiado, publica una versión nueva y tu gestor de addons la descarga. Si una web falla o cambia, se mantiene la copia anterior y se abre un aviso en [Issues](../../issues). También se puede lanzar a mano desde la pestaña **Actions** → "Actualizar builds" → **Run workflow**.

## Añadir guías para todos

Edita `tools/links.txt` (puedes hacerlo directamente en GitHub). Pon una línea por guía o build:

```
Nombre | Tipo | enlace
```

`Tipo` es opcional y puede ser Leveo, PvE o PvP. Si el enlace es una guía, se leen todas las builds que enlaza y se vuelven a leer en cada actualización.

## Probarlo en local

```
python tools/update_builds.py
```

Necesita Python 3.10 o superior. Después, `/reload` en el juego.
