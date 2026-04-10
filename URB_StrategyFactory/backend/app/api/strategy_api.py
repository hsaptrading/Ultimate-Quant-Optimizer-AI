from fastapi import APIRouter, File, UploadFile, HTTPException, Body, Form
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
import shutil
import os
import re
import hashlib

from ..core.mql5_parser import MQL5Parser
from ..core.state import strat_state
from ..strategies.urb_killzone import URBKillzoneStrategy
from ..core.ai_translator import AITranslator

router = APIRouter()

# --- Registry ---
# TODO: Scan directory or use proper plugin registry
strategies_registry = {
    "urb_killzone": URBKillzoneStrategy
}

# --- Models ---
class StrategyResponse(BaseModel):
    slug: str
    name: str
    description: str

class SetStrategyRequest(BaseModel):
    slug: str

class StrategyInput(BaseModel):
    name: str
    type: str 
    original_type: Optional[str] = None
    default: Any
    label: str
    category: str
    options: Optional[List[Dict[str, str]]] = None

class StrategyMetadata(BaseModel):
    filename: str
    inputs: List[StrategyInput]
    python_code: Optional[str] = None
    ai_status: Optional[str] = None

# --- Endpoints ---

@router.get("/list", response_model=List[StrategyResponse])
def list_strategies():
    """List all available strategies in the factory."""
    results = []
    for slug, cls in strategies_registry.items():
        try:
             inst = cls()
             results.append({
                 "slug": slug,
                 "name": inst.display_name,
                 "description": inst.description
             })
        except Exception as e:
            print(f"Error instantiating {slug}: {e}")
            
    # Include currently active custom strategy if any
    if strat_state.active_schema and getattr(strat_state.active_schema, "filename", None):
        custom_slug = strat_state.active_schema.filename.replace(".mq5", "").lower().replace(" ", "_")
        results.append({
            "slug": custom_slug,
            "name": strat_state.active_schema.filename,
            "description": "Custom Intelligence (AI Digital Twin)"
        })
            
    return results

@router.post("/set_active")
def set_active_strategy(req: SetStrategyRequest):
    """Set the strategy to be optimized."""
    if strat_state.active_schema and getattr(strat_state.active_schema, "filename", None):
        custom_slug = strat_state.active_schema.filename.replace(".mq5", "").lower().replace(" ", "_")
        if req.slug == custom_slug:
            strat_state.active_name = strat_state.active_schema.filename
            strat_state.active_strategy_slug = req.slug
            return {"message": "Custom Strategy Activated", "current": strat_state.active_name}

    if req.slug in strategies_registry:
        cls = strategies_registry[req.slug]
        inst = cls()
        
        strat_state.active_name = inst.display_name
        strat_state.active_strategy_slug = req.slug
        # When switching back to a default, clear the custom schema so endpoints.py loads defaults
        strat_state.active_schema = None 
        
        return {"message": "Strategy Activated", "current": strat_state.active_name}
        
    raise HTTPException(status_code=404, detail="Strategy not found")

@router.post("/import", response_model=StrategyMetadata)
async def import_strategy(
    file: UploadFile = File(...),
    ai_mode: str = Form("ollama"),
    ai_key: str = Form("")
):
    """
    Upload .mq5 to parse inputs and optionally translate logic via AI.
    """
    try:
        strategies_dir = os.path.abspath(os.path.join(os.getcwd(), "strategies_source"))
        if not os.path.exists(strategies_dir):
            os.makedirs(strategies_dir)
        
        file_path = os.path.join(strategies_dir, file.filename)
        
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        # 1. Parsing Tradicional (UI Inputs)
        parser = MQL5Parser(file_path)
        if not parser.read_file():
            raise HTTPException(status_code=400, detail="Could not read saved file.")
            
        extracted_inputs = parser.parse_inputs()
        
        # 2. Generacion AI de Logica (Opcional)
        py_code = None
        status = "AI Translation Skipped"
        
        try:
            with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                mq5_content = f.read()

            # Hash check (The Vault System)
            current_hash = hashlib.md5(mq5_content.encode('utf-8')).hexdigest()
            filename_safe = file.filename.replace('.mq5', '.py').replace(' ', '_').lower()
            gen_path = os.path.abspath(os.path.join(os.getcwd(), "app", "strategies", filename_safe))
            hash_path = gen_path.replace('.py', '.hash')

            # Verify if strategy is already cached and unmodified
            if os.path.exists(gen_path) and os.path.exists(hash_path):
                with open(hash_path, "r", encoding="utf-8") as h_file:
                    saved_hash = h_file.read().strip()
                if saved_hash == current_hash:
                    with open(gen_path, "r", encoding="utf-8") as f:
                        py_code = f.read()
                    status = "Success (Loaded from Vault)"
                    
                    # Cargar estado en RAM para el frontend
                    strat_state.active_schema = StrategyMetadata(
                        filename=file.filename,
                        inputs=extracted_inputs,
                        python_code=py_code,
                        ai_status=status
                    )
                    return {
                        "filename": file.filename,
                        "inputs": extracted_inputs,
                        "python_code": py_code,
                        "ai_status": status
                    }

            # If no cache or hash mismatch, call AI
            final_key = ai_key if ai_key else os.getenv("GROQ_API_KEY")
            translator = AITranslator(mode=ai_mode, api_key=final_key)
            translated_result = translator.translate_code(mq5_content)
            
            if "[ERROR" in translated_result:
                status = translated_result
            else:
                py_code = translated_result
                status = "Success"
                
                # Guardar el codigo generado y su hash en la boveda
                os.makedirs(os.path.dirname(gen_path), exist_ok=True)
                with open(gen_path, "w", encoding="utf-8") as py_file:
                    py_file.write(f"# Auto-Generated by URB AI Translator\\n{py_code}")
                with open(hash_path, "w", encoding="utf-8") as h_file:
                    h_file.write(current_hash)
                    
        except Exception as ai_e:
             status = f"AI Error: {ai_e}"
             print(status)
        
        return {
            "filename": file.filename,
            "inputs": extracted_inputs,
            "python_code": py_code,
            "ai_status": status
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/select")
def select_strategy(strategy: StrategyMetadata):
    """
    Sets the active strategy schema for the Builder to use.
    """
    strat_state.active_schema = strategy
    strat_state.active_name = strategy.filename
    return {"status": "ok", "message": f"Strategy {strategy.filename} selected active."}

class SetFileContent(BaseModel):
    content: str

@router.post("/parse-set")
async def parse_set_file_endpoint(data: SetFileContent):
    """
    Parses content of a .set file and returns structural config.
    """
    try:
        parser = MQL5Parser("")
        parsed_params = parser.parse_set_file(data.content)
        return parsed_params
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
