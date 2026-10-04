# Zbuilds

Addon de **WoW Forever** que reúne builds de talentos de varias webs y te deja verlas, compararlas y aprenderlas en el juego.

- **Fuentes:** builds populares de [Talents Forever](https://talentsforever.com) (datos CC BY 4.0) y las guías de [Icy Veins](https://www.icy-veins.com/wow-forever/), [Warcraft Tavern](https://www.warcrafttavern.com/forever/guides/), [Method](https://www.method.gg/wow-forever) y [WoW Forever Builds](https://wowforeverbuilds.com), más las guías extra de `tools/links.txt`.
- **Siempre válidas:** cada build se traduce al árbol actual del juego por el nombre de sus talentos, y se descarta si usa un talento que ya no existe o no se puede aprender (por ejemplo, si un talento ha cambiado de fila).
- **Pestañas por especialización:** se abre en la tuya. Puedes filtrar por tipo (Leveo, PvE, PvP), por web y con un buscador.
- **Árboles:** muestran los rangos de la build y, con el color del borde, lo que ya tienes aprendido. Incluyen las flechas de requisitos.
- **Comparar:** clic derecho en otra build, o "Comparar con mis talentos".
- **Aprender puntos libres:** gasta tus puntos siguiendo el orden de la build (fuera de combate).
- **+ Importar enlace:** pega un enlace de build de talentsforever.com o de la calculadora de Icy Veins. Funciona sin conexión y se guarda en tu cuenta.

Comando: `/zb`

## Instalación

- **CurseForge / WowUp:** instala "Zbuilds"; tu gestor de addons te avisará de cada actualización.
- **A mano:** descarga el `.zip` de la última [versión](../../releases) y descomprímelo en `World of Warcraft\<cliente>\Interface\AddOns\`.

## Cómo se actualizan las builds

Los addons de WoW no pueden conectarse a internet, así que el trabajo lo hace GitHub: cada día ejecuta `tools/update_builds.py`. Si alguna build ha cambiado, publica una versión nueva y tu gestor de addons la descarga. También se puede lanzar a mano desde la pestaña **Actions** → "Actualizar builds" → **Run workflow**.

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
