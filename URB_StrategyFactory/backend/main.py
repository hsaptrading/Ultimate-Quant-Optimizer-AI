from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import sys
import os

from app.api.endpoints import router as api_router
from app.api.generation import router as gen_router
from app.api.data_api import router as data_router
from app.api.strategy_api import router as strategy_router

# Versión y Saludo
VERSION = "0.1.0"

app = FastAPI(title="URB Strategy Engine", version=VERSION)

# Config CORS (Allow Electron Frontend)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # In local desktop app, * is fine
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix="/api/config") # Note: changed prefix for organization if needed, but keeping simple
app.include_router(api_router, prefix="/api") # Kept for compatibility with previous code
app.include_router(gen_router, prefix="/api/builder")
app.include_router(data_router, prefix="/api/data") # Kept for compatibility with previous code
app.include_router(strategy_router, prefix="/api/strategy") # New Universal Strategy API
app.include_router(strategy_router, prefix="/api/strategies") # Alias for frontend compatibility

@app.get("/")
def read_root():
    return {"status": "ok", "message": "URB Engine Online", "version": VERSION}

@app.get("/health")
def health_check():
    # Verificación básica
    return {"status": "healthy", "python_version": sys.version}

if __name__ == "__main__":
    print(f"Iniciando URB Engine v{VERSION}...")
    print("Verificacion de imports basicos: OK")
    uvicorn.run(app, host="127.0.0.1", port=8000)
