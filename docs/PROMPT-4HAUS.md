# Prompt para el proyecto 4haus.us
Pega todo lo que sigue en el chat o proyecto donde construyes 4haus.

---

Quiero convertir **4haus.us** en un **estudio creativo con IA** que otras apps puedan usar como proveedor: imágenes, video corto, música instrumental, voz y efectos de sonido, al estilo de Epidemic Sound (música con licencia), Hailuo/MiniMax y Seedance (video desde imagen). El primer cliente es mi app **The Eagle Life** (theaglelife.com/app), un lifebook de crecimiento espiritual con un **Vision Board interactivo**. Ahí el usuario crea imágenes de sus sueños y metas a partir de su foto. La app se las muestra al despertar, al hacer ejercicio o al alcanzar una meta, con música y una voz que le lee sus declaraciones.

Constrúyelo en este orden y confírmame cada etapa antes de seguir.

## 1. Lo que 4haus debe hacer
1. **Imágenes:** a partir de un texto y, opcionalmente, una foto de referencia del usuario, generar imágenes donde la persona sea reconocible. Estilos: foto realista, cinemático, ilustración y óleo. Formatos 4:5, 9:16 y 16:9.
2. **Video corto:** animar una imagen de 5 a 10 s con movimiento suave de cámara (imagen a video).
3. **Música instrumental:**
   - Catálogo buscable por *momento* (despertar, oración, enfoque, ejercicio, celebración), BPM, duración y energía.
   - Solo pistas con **licencia comercial clara**: generadas con IA con licencia, o de un catálogo licenciado con API.
   - Cada pista guarda su licencia.
4. **Voz (texto a voz) en español latino**, natural y cálida. Al menos dos voces (hombre y mujer) y velocidad ajustable.
5. **Efectos de sonido y fondos:** lluvia, naturaleza, ruido marrón y ruido rosa.

## 2. La API REST que The Eagle Life ya espera (no cambies estas rutas)
- **Autenticación:** `Authorization: Bearer <API_KEY del cliente>`. Cada app cliente tiene su llave, sus límites y su facturación.
- **Imágenes:** `POST /v1/images`
  - Recibe `{ prompt, style, aspect_ratio, reference_image_url?, user_ref, client_ref }`.
  - Responde `{ job_id }` si es asíncrono, o `{ images:[{ url }] }` si es inmediato.
- **Trabajos:** `GET /v1/jobs/{id}` responde `{ status: "queued"|"running"|"succeeded"|"failed", images?:[{url}], video?:{url}, error? }`.
- **Video:** `POST /v1/videos` recibe `{ image_url, prompt, seconds, aspect_ratio, client_ref }` y responde `{ job_id }`.
- **Música:** `GET /v1/music?mood=wake|prayer|focus|exercise|goal&minutes=N&bpm=` responde `{ tracks:[{ id, title, url, duration, bpm, license }] }`.
- **Voz:** `POST /v1/voice` recibe `{ text, voice, language:"es", speed? }` y responde `{ url }` (mp3).
- **Sonidos:** `GET /v1/sfx?q=lluvia` responde `{ items:[{ id, title, url, license }] }`.

Reglas generales de la API:
- Las URLs que devuelvas deben ser firmadas y durar al menos 1 hora. La app descarga las imágenes y las guarda en su propio almacenamiento.
- Webhook opcional `POST {callback_url}` cuando un trabajo termine.
- Errores en JSON `{ error:{ code, message } }` con mensajes claros en español.

## 3. Servidor MCP
Además de la API, publica un **servidor MCP** (HTTP remoto, con OAuth o llave) con las mismas herramientas: `generate_image`, `generate_video`, `get_job`, `search_music`, `text_to_speech` y `search_sfx`. Así cualquier agente de IA (Claude u otros) puede usar 4haus.

Ojo: una app web no se conecta directo a un MCP. The Eagle Life usará la **API REST** desde su servidor (una Edge Function de Supabase). El MCP es para agentes.

## 4. Proveedores
Evalúa y recomiéndame, con costos por unidad, servicios con **API y licencia comercial**:
- Imagen con identidad desde foto: modelos tipo Flux con referencia de rostro, vía fal.ai o Replicate.
- Video: Hailuo/MiniMax, Seedance o Kling.
- Música: generación con licencia comercial, o un catálogo licenciado con API.
- Voz: ElevenLabs o Azure Neural en español.

Abstrae los proveedores detrás de 4haus para poder cambiarlos sin tocar a los clientes.

## 5. Seguridad y ética (obligatorio)
- Usar la foto solo con el **consentimiento** del propio usuario adulto. The Eagle Life lo pide antes de enviarla.
- **Rechazar:**
  - Fotos de menores como referencia.
  - Rostros de terceros o de figuras públicas.
  - Desnudos, violencia y contenido sexual.
  - Logos o personajes con derechos de autor.
- Moderar el texto y la imagen antes y después de generar.
- Borrar las fotos de referencia en 24 horas como máximo.
- No usar el material de los usuarios para entrenar modelos.
- Todas las imágenes y videos llevan una marca invisible de contenido generado con IA, si el proveedor la ofrece.

## 6. Negocio
- Créditos por cliente y por usuario final (`user_ref`).
- Precio por imagen, video, minuto de voz y pista.
- Panel para ver consumo, ingresos y costos.
- Límites por minuto para evitar abusos.

The Eagle Life necesita estos cupos mensuales por usuario:

| Plan | Imágenes al mes |
|---|---|
| Prueba | 3 |
| Semillas ($7) | 12 |
| Eagle ($17) | 40 |

Cotízame el costo para 1 000, 10 000 y 50 000 usuarios.

## 7. Entregables
1. Arquitectura propuesta y proveedores con costos.
2. La API REST de la sección 2 funcionando en `https://api.4haus.us`, con documentación y una llave de prueba para The Eagle Life.
3. El servidor MCP.
4. Una página pública en 4haus.us que presente el estudio a otros clientes.

Cuando esté lista la API, entrégame:
- `FOURHAUS_API_URL`
- `FOURHAUS_API_KEY` (de prueba y de producción)

Las pegaré en los secretos de Supabase de The Eagle Life.
