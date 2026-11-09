// Conexión con Supabase. Esta llave es pública (publishable); lo que protege
// los datos de cada usuario son las reglas creadas con los archivos .sql.
window.APP_CONFIG = {
  supabaseUrl: "https://cvuiupvqtmcgdssxdpbx.supabase.co",
  supabaseAnonKey: "sb_publishable_tD4_KzP1sTotUqAopREPeg_ITC43LRX",

  // Pagos con Culqi: pega aquí tu LLAVE PÚBLICA (pk_test_… para probar, pk_live_… en producción).
  // Vacía = los botones de pago dicen "Pagos disponibles pronto".
  culqiPublicKey: "",
  currency: "USD",     // moneda que aparece primero: "USD" o "PEN". El usuario puede cambiar a soles al pagar.

  // Mercado Pago: ponlo en true cuando publiques las funciones «mercadopago» y «mp-webhook»
  // y guardes MP_ACCESS_TOKEN en Supabase → Edge Functions → Secrets.
  mercadoPago: false,

  // Enlace a la comunidad (grupo de WhatsApp, Telegram, Skool…). Lo ven los planes Bootcamper o superiores.
  communityUrl: ""
};
