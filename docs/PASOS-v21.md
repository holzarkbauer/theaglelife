# The Eagle Life · v21 · contenido editable desde el Backoffice

## 1. Base de datos
Supabase → SQL Editor → + New → pega `supabase/9-supabase-medios-voces.sql` → Run.
Crea las tablas de sonidos, videos de fondo y voces, el bucket público «medios» y carga los 20 sonidos y 54 videos actuales.
(Antes deben estar corridos los pasos 1 al 8.)

## 2. Función «visionboard»
Supabase → Edge Functions → visionboard → Code → reemplaza todo con `supabase/functions/visionboard/index.ts` → Deploy.
Agrega la acción «voices» (catálogo de voces de 4haus para el Backoffice) y respeta el plan mínimo de cada voz.

## 3. Uso
- Backoffice → Contenido → **Sonidos** / **Videos de fondo**: crear, renombrar, ordenar, ocultar o borrar categorías; subir archivos (.mp3 / .mp4) y moverlos de categoría. La imagen fija de cada video se genera sola al subirlo.
- Backoffice → Contenido → **Voces**: «Traer voces de 4haus» (cuando 4haus esté conectado) o «+ Agregar voz» con el ID que te dé 4haus. Elige quién puede usarla (Gratis / Prueba y planes / Solo Eagle) y cuál es la voz por defecto.
- Los cambios se ven en la app al volver a abrirla.

Acceso: solo cuentas de la tabla `admins`, con contraseña + código 2FA (paso 8).
