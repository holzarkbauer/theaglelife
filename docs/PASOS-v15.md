# The Eagle Life · versión 15 · pasos para publicarla

Novedades: backoffice con **contraseña + código 2FA**, color verde de la marca en el backoffice, pago con **Culqi en dólares o soles** y **Mercado Pago en dólares**.

Haz los pasos en este orden. Las claves secretas se pegan en Supabase, nunca en el chat ni en `config.js`.

## 1. Base de datos (Supabase → SQL Editor → + New → pegar → Run)
Corre, en orden, los que aún no hayas corrido (se pueden repetir sin dañar nada):
1. `supabase/5-supabase-backoffice.sql`
2. `supabase/6-supabase-v10.sql`
3. `supabase/7-supabase-visionboard.sql`
4. **Nuevo:** `supabase/8-supabase-seguridad-pagos.sql`. Exige el código 2FA para todo lo de administrador, guarda los precios en soles y prepara Mercado Pago.

> Después del paso 8, los datos del backoffice solo se abren con el código del celular. Haz el paso 4 de esta guía el mismo día.

## 2. Funciones (Supabase → Edge Functions)
| Nombre exacto | Archivo | Cómo |
|---|---|---|
| `coach` | `supabase/coach-index.ts` | Si ya existe: ábrela → Code → reemplaza todo → Deploy. Si no: Deploy a new function → Via Editor. |
| `pago` | `supabase/pago-index.ts` | **Actualizada** (soles y dólares). Reemplaza todo → Deploy. |
| `culqi-webhook` | `supabase/culqi-webhook-index.ts` | En Details, **desactiva «Verify JWT»**. |
| `visionboard` | `supabase/visionboard-index.ts` | Puente con 4haus. |
| `mercadopago` | `supabase/mercadopago-index.ts` | **Nueva.** Crea el pago y devuelve el enlace de Mercado Pago. |
| `mp-webhook` | `supabase/mp-webhook-index.ts` | **Nueva.** En Details, **desactiva «Verify JWT»** (Mercado Pago no inicia sesión). |

## 3. Secretos (Edge Functions → Secrets → Add new secret)
- `ANTHROPIC_API_KEY`: sin ella el agente dice «No se pudo contactar al coach».
- `CULQI_SECRET_KEY` y los planes en dólares: `CULQI_PLAN_SEMILLAS_TRIAL`, `CULQI_PLAN_SEMILLAS`, `CULQI_PLAN_EAGLE`.
- **Nuevos, planes en soles:** `CULQI_PLAN_SEMILLAS_TRIAL_PEN`, `CULQI_PLAN_SEMILLAS_PEN`, `CULQI_PLAN_EAGLE_PEN` (paso 5).
- **Nuevo, Mercado Pago:** `MP_ACCESS_TOKEN` (paso 6). Opcional: `MP_CURRENCY` = `USD` (por defecto).
- `FOURHAUS_API_URL` y `FOURHAUS_API_KEY`: cuando 4haus tenga su API.

## 4. Contraseña + código 2FA del backoffice
1. Supabase → **Authentication → Sign In / Providers → Multi-Factor (MFA)**: revisa que **TOTP (App Authenticator)** esté **Enabled**. Normalmente ya lo está.
2. Usa una contraseña larga y solo tuya para tu cuenta de The Eagle Life (12 caracteres o más). Si quieres cambiarla: en la app, cierra sesión → «¿Olvidaste tu contraseña?».
3. Instala en tu celular **Google Authenticator**, **Microsoft Authenticator** o **1Password**.
4. Entra a theaglelife.com/app con tu cuenta → ☰ → **Backoffice**.
5. Escribe tu contraseña → aparece un **código QR** → en la app del celular toca **+** → **Escanear código QR**.
6. Escribe los 6 dígitos que muestra el celular → **Activar y entrar**.
7. Desde ahora, cada vez que entres al backoffice: contraseña + código. Si lo dejas 20 minutos sin usar, se bloquea solo.

**Si pierdes el celular:** Supabase → SQL Editor → corre esto y vuelve al paso 4 para escanear un QR nuevo:
```sql
delete from auth.mfa_factors where user_id = (select id from auth.users where email = 'arkholzbau@gmail.com');
```

## 5. Culqi en soles (CulqiPanel → Suscripciones → Crear plan)
Crea tres planes más, en **PEN**:
- **Semillas con prueba (S/)**: S/ 27, mensual, periodo de prueba 7 días → `CULQI_PLAN_SEMILLAS_TRIAL_PEN`.
- **Semillas (S/)**: S/ 27, mensual → `CULQI_PLAN_SEMILLAS_PEN`.
- **Eagle (S/)**: S/ 65, mensual → `CULQI_PLAN_EAGLE_PEN`.

La prueba en soles cuesta S/ 4. Estos precios están en `8-supabase-seguridad-pagos.sql` (`prices_pen`, en céntimos). Si los cambias, cambia también los planes de Culqi para que coincidan.

## 6. Mercado Pago (en dólares)
1. Entra a **mercadopago.com.pe/developers** → **Tus integraciones** → **Crear aplicación** (nombre: The Eagle Life · producto: Suscripciones y Checkout Pro).
2. **Credenciales de producción** → copia el **Access Token** y pégalo en Supabase como `MP_ACCESS_TOKEN`. No lo pegues en el chat.
3. **Webhooks → Configurar notificaciones** → URL de producción:
   `https://cvuiupvqtmcgdssxdpbx.supabase.co/functions/v1/mp-webhook`
   Eventos: **Pagos** y **Planes y suscripciones** → Guardar.
4. En `theaglelife/app/config.js` cambia `mercadoPago: false` por `mercadoPago: true`.
5. Si al pagar sale un error de moneda, tu cuenta de Mercado Pago no acepta dólares: agrega el secreto `MP_CURRENCY` = `PEN` y se cobrará en soles.

Con Mercado Pago la prueba es de **7 días gratis** (Mercado Pago no permite cobrar $1 y luego $7 en la misma suscripción). Después cobra Semillas cada mes.

## 7. Subir a la web (Netlify)
Netlify → tu sitio de theaglelife.com → **Deploys** → arrastra la carpeta `theaglelife` completa al recuadro *Drag and drop*. En 1 minuto queda en www.theaglelife.com/app.

## 8. Probar
1. Incógnito → theaglelife.com/app: aparece el cuestionario, sin pedir registro.
2. Backoffice (contraseña + código) → **Sistema → Configuración**: cada integración debe decir **Conectado**.
3. Planes → elige Semillas → prueba los tres medios: Tarjeta US$, Tarjeta S/ y Mercado Pago. Usa las llaves y tarjetas de prueba antes de pasar a producción.
4. Cancela la suscripción de prueba desde **Planes**.

## Límites de IA (Backoffice → Límites y metas)
| Plan | Precio | Haiku | Opus | Costo máximo de IA |
|---|---|---|---|---|
| Gratis | $0 | 0 | 0 | $0 |
| Prueba 7 días | $1 / S/ 4 | 600 mil | 15 mil | ≈ $0.19 |
| Semillas | $7 / S/ 27 al mes | 4 millones | 115 mil | ≈ $1.38 |
| Eagle | $17 / S/ 65 al mes | 8 millones | 330 mil | ≈ $3.39 |
