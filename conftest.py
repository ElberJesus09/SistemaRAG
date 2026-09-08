"""Pruebas aisladas: nunca usar servicios ni credenciales reales en la suite."""
import os

os.environ.update({
    "SUPABASE_URL": "https://pruebas.supabase.co",
    "SUPABASE_ANON_KEY": "anon-de-prueba",
    "SUPABASE_SERVICE_ROLE_KEY": "servicio-de-prueba",
    "GEMINI_API_KEY": "gemini-de-prueba",
})
