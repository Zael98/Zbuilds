# Zbuilds

Addon de **WoW Forever** que reúne builds de talentos de varias webs y te deja verlas, compararlas y aprenderlas en el juego.

- **Fuentes:** builds populares de [Talents Forever](https://talentsforever.com) (datos CC BY 4.0) y las guías de [Icy Veins](https://www.icy-veins.com/wow-forever/), [Warcraft Tavern](https://www.warcrafttavern.com/forever/guides/), [Method](https://www.method.gg/wow-forever), [WoW Forever Builds](https://wowforeverbuilds.com), [RankedBoost](https://rankedboost.com/world-of-warcraft/forever/build/) y [WoW Forever Talent](https://wowforevertalent.com/builds/) (solo sus planes propios), más las guías extra de `tools/links.txt`.
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
- **En la ventana de talentos del juego:** una barra en la franja dorada con el selector de build, la predicción del siguiente punto ("disponible ya" o "nivel 31", más los dos siguientes), el brillo numerado sobre el árbol del juego y "Aprender N puntos".
- **Loadouts:** guarda builds como loadout, ponles nombre y rota entre ellos con las flechas o la rueda en la ventana de talentos (clic derecho en el selector para renombrar). Como en Classic, para cambiar de build hay que olvidar los talentos en el instructor; después, un clic la aplica entera.
- **Legacy:** pestaña con los tres árboles de Legacy (Profesiones, Aventura, Recursos), tus rangos y puntos (disponibles, gastados y conseguidos sobre 81), y planes por objetivo de WoW Forever Builds con su orden de puntos.
- **Desafíos de Legacy:** los 66 desafíos, hechos y pendientes, con su progreso y ordenados por facilidad. Un clic abre el desafío en la ventana Legacy Challenges del juego.
- **Recordatorio del instructor:** al subir de nivel, un banner en el centro de la pantalla con los hechizos y rangos nuevos que puedes aprender, el siguiente talento de tu build, el coste total y si te llega el oro, y lo que costarán los próximos 5 niveles. Los hechizos que no tienes en tus barras salen en gris como opcionales. Las mejoras para tu mascota o tu demonio van aparte. Los precios salen de Wowhead y se cambian por los reales al abrir tu instructor.
- **Entrenar todo:** botón en la ventana del instructor que aprende de un clic todo lo que puedes (Mayús+clic: solo lo de tus barras).
- **Banner de Legacy:** al completar un desafío, con el siguiente perk de tu plan.
- **Opciones:** pestaña para activar o quitar el banner, su sonido y su contenido, la lista en el chat, el botón del minimapa y la duración del banner.
- **Accesos:** botón en el minimapa (`/zb minimap` lo oculta) y menú de addons del juego.

Comandos: `/zb` abre la ventana · `/zb minimap` oculta o muestra el botón del minimapa · `/zb trainer` lista lo que puedes aprender en tu instructor · `/zb trainertest` muestra el banner del instructor · `/zb options` abre las opciones · `/zb diag` comprueba qué permite este cliente

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

## Pruebas

`tests/run.py` carga el addon en Lua 5.1 con el API de WoW simulado y comprueba talentos, importación, ventana, loadouts, Legacy, desafíos, instructor, banners y opciones en los 11 idiomas. GitHub las ejecuta antes de publicar cualquier versión; si fallan, no se publica. Las pruebas usan una copia fija de los datos (`tests/fixtures/data.lua`); sobre los datos reales solo se comprueban los enlaces de cada build y, como aviso que no bloquea, si encajan con un volcado real del juego (`tests/fixtures/game_dump.lua`). Tras un parche ese volcado queda viejo: `/zb legacy` con cualquier personaje, `/reload` y copiar `ZbuildsDB.legacyDump` de `SavedVariables/Zbuilds.lua` a la fixture como `GAME_DUMP`.

```
pip install "lupa>=2"
python tests/run.py
```

## Probarlo en local

```
python tools/update_builds.py
```

Necesita Python 3.10 o superior. Después, `/reload` en el juego.
