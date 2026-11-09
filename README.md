# The Eagle Life

Lifebook para el crecimiento espiritual: tracker de 90 días, declaraciones, guías, Biblia, coach con IA, Vision Board y tienda.

- `app/`, `index.html` y demás: el sitio que se publica en Netlify (www.theaglelife.com).
- `supabase/*.sql`: base de datos, en orden del 1 al 8.
- `supabase/functions/`: Edge Functions (coach, pago, culqi-webhook, visionboard, mercadopago, mp-webhook).
- `docs/PASOS-v15.md`: pasos para publicar.

Las claves secretas van en Supabase → Edge Functions → Secrets. Nunca en este repositorio.
