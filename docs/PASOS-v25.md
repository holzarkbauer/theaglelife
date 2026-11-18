# The Eagle Life · v25: pasos para José

## Qué cambió
- **Acceso con código de 6 dígitos** por correo. Si es la primera vez, la cuenta se crea sola. La contraseña sigue como opción.
- **Idiomas:** español, inglés y portugués. La app elige según el idioma del celular y se puede cambiar en ☰ Menú. La IA responde en el idioma elegido. La Biblia en inglés abre en KJV.
- **Cuestionario inicial con 3 caminos:**
  - nuevo creyente: guía espiritual con IA + Identidad en Cristo + Propósito + Hombría al Máximo;
  - creyente que quiere crecer;
  - crecimiento personal con principios bíblicos.
- **Guía 3 · Descubre tu propósito** (6 sesiones). Se vincula con el libro «Una vida con propósito» cuando lo subas.
- **IA gratis:** unos 15 mensajes al mes (30 000 tokens). Al agotarse, invita a la prueba de 7 días por $1.
- **Tienda:** libros con **★ Incluido en tu suscripción** y socio + % (ej. CMN 90%).
- **Comunidad:** enlace a Grupos de hombres de Camino de Vida en la Guía 1.
- **Lector tipo libro:**
  - títulos en negrita;
  - sin el título repetido en cada página;
  - número de página al pie con ‹ ›;
  - ☰ Índice de capítulos;
  - ir a una página escribiendo el número.

## 1. Supabase · SQL (una sola vez)
SQL Editor → pega y ejecuta `supabase/11-supabase-acceso-rutas.sql`.
Si aún no ejecutaste del 4 al 10, ejecútalos antes, en orden.

## 2. Supabase · correo con código
1. **Authentication → Sign In / Providers → Email**: activa *Enable Email provider* y *Allow new users to sign up*.
2. **Authentication → Emails → Magic Link**: reemplaza el contenido por:

```html
<h2>Tu código para entrar a The Eagle Life</h2>
<p style="font-size:28px;letter-spacing:6px"><b>{{ .Token }}</b></p>
<p>Escríbelo en la app. Vence en 1 hora. Si no lo pediste, ignora este correo.</p>
```

3. Haz lo mismo en **Confirm signup** (mismo texto con `{{ .Token }}`).
4. **SMTP propio (muy recomendado):** el correo de Supabase por defecto solo envía unos pocos mensajes por hora.
   - Crea una cuenta en Resend (resend.com) y verifica el dominio theaglelife.com.
   - En Authentication → Emails → SMTP Settings pon: host `smtp.resend.com`, puerto `465`, usuario `resend`, y la API key de Resend como contraseña.
   - La API key la pegas tú ahí, nunca en el chat.

## 3. Subir «Hombría al Máximo» (muestra privada para CMN)
1. Entra a la app con tu cuenta de administrador → **Tienda → Administrador · publicar un título**.
2. Llena:
   - Título «Hombría al Máximo», autor «Edwin Louis Cole».
   - Visibilidad **Privada · solo revisión (no se vende)**.
   - Correos invitados: los de CMN.
   - Marca **★ Incluido en la suscripción**, socio «CMN», 90%.
3. En **Elegir libro y publicar** escoge el archivo **hombria-al-maximo.json** que te envié. Es el libro ya convertido: títulos, capítulos e índice.

> No subas el PDF escaneado: son fotos de páginas sin texto.

Los manuales (español e inglés) sí tienen texto: puedes subirlos como PDF de la misma forma.

## 4. Lo que falta de tu parte
- PDF de «Una vida con propósito» (Rick Warren) para la muestra privada.
- Pagos: llave pública de Culqi o activar Mercado Pago (las llaves secretas van solo en Supabase Secrets).
