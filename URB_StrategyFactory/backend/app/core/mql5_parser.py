import re
import os
from typing import Dict, List, Any

class MQL5Parser:
    """
    Analizador de Código MQL5.
    Extrae la configuración de variables 'input' y 'sinput' para generar
    la interfaz de usuario (UI) automáticamente.
    """
    
    def __init__(self, filepath: str):
        self.filepath = filepath
        self.raw_content = ""
        self.inputs = [] # Lista ordenada de inputs
        
    def read_file(self) -> bool:
        if not os.path.exists(self.filepath):
            return False
        with open(self.filepath, "r", encoding="utf-8", errors="ignore") as f:
            self.raw_content = f.read()
        return True

    def parse_enums(self) -> Dict[str, List[Dict[str, str]]]:
        """
        Escanea el archivo buscando definiciones de enum personalizadas:
        enum ENUM_RISK_TYPE {
            RISK_PERCENT, // % del Balance
            RISK_FIXED_LOTS, // Lotes Fijos
            RISK_FIXED_MONEY // $ Fijos por Operación
        };
        """
        enums = {}
        # Regex para bloque enum completo
        # enum Nombre { ... };
        block_pattern = re.compile(r"enum\s+(\w+)\s*\{([^}]+)\};", re.DOTALL | re.IGNORECASE)
        
        blocks = block_pattern.findall(self.raw_content)
        
        for enum_name, content in blocks:
            options = []
            # Dividir por comas, ignorando saltos de línea
            # Problema: los comentarios pueden tener comas. Mejor regex por línea o token.
            # Simpler approach: split by comma, but clean comments first? No, comments are key.
            # Split by lines first? No, content can be multi-line.
            # Split by ',' but be careful. Actually MQL5 enums are comma separated.
            # Regex for each item: NAME (= value)? (// comment)?
            
            # Vamos a limpiar comentarios de bloque /* ... */ primero si fuera necesario, pero MQL5 usa //
            
            # Tokenizar por comas, asumiendo que no hay comas en comentarios (riesgoso pero común)
            # Mejor: Iterar sobre el contenido buscando patrones "NOMBRE ... ,"
            
            # Regex para capturar items: 
            # (Identificador) (= Valor)? (,)? (// Comentario)?
            # Modificado para permitir coma opcional antes del comentario
            item_pattern = re.compile(r"([a-zA-Z_]\w*)\s*(?:=\s*[^,/]+)?\s*(?:,\s*)?(?://\s*(.*))?", re.M)
            
            # Limpiar saltos de línea y espacios raros para facilitar
            # content = content.replace("\n", " ") # No, comments need newline detecion or stripping
            
            # Divide y vencerás: Split lines to handle // comments effectively
            lines = content.split('\n')
            clean_content = ""
            for line in lines:
                # Extraer comentario de línea si existe para preservarlo asociado al token
                # Trick: Process line by line.
                # Find valid identifier on line
                match = item_pattern.search(line)
                if match:
                    opt_name = match.group(1)
                    opt_comment = match.group(2) if match.group(2) else opt_name
                    # Save directly
                    options.append({
                        "value": opt_name, # El valor interno es el nombre del enumerador
                        "label": opt_comment.strip() # La etiqueta es el comentario
                    })
            
            if options:
                enums[enum_name] = options
                
        return enums

    def parse_inputs(self) -> List[Dict[str, Any]]:
        extracted_enums = self.parse_enums()
        
        # Regex combinada para capturar Group Titles y Inputs en orden
        # Grupo 1 (Category): input group "Title"
        # Grupo 2-6 (Input): scope type name = val; // comment
        combined_pattern = re.compile(
            r'input\s+group\s+"([^"]+)"|'  # Group 1: Category Name
            r'(input|sinput)\s+([\w:]+)\s+(\w+)\s*=\s*([^;]+);\s*(?://\s*(.*))?', # Groups 2-6
            re.IGNORECASE | re.MULTILINE
        )
        
        matches = combined_pattern.finditer(self.raw_content)
        
        extracted_inputs = []
        current_category = "General"
        
        for match in matches:
            # Caso 1: Es un Grupo
            if match.group(1):
                current_category = match.group(1)
                continue
            
            # Caso 2: Es un Input (si no es grupo y matcheó parte 2)
            if not match.group(2): continue

            inp_scope = match.group(2)
            inp_type = match.group(3)
            inp_name = match.group(4)
            inp_val_raw = match.group(5)
            inp_comment = match.group(6)
            
            value_clean = inp_val_raw.strip()
            # Limpiar comentarios extraños si los hay
            if value_clean.endswith('"') and value_clean.startswith('"'):
                value_clean = value_clean.strip('"')

            label = inp_comment.strip() if inp_comment else inp_name
            
            py_type = "string"
            options = []
            
            if inp_type in extracted_enums:
                py_type = "enum"
                options = extracted_enums[inp_type]
            elif "ENUM_" in inp_type:
                py_type = "enum"
            elif inp_type in ["int", "long", "short", "ulong", "uint"]:
                py_type = "int"
                try: value_clean = int(value_clean)
                except: pass
            elif inp_type in ["double", "float"]:
                py_type = "float"
                try: value_clean = float(value_clean)
                except: pass
            elif inp_type == "bool":
                py_type = "bool"
                if str(value_clean).lower() == "true": value_clean = True
                elif str(value_clean).lower() == "false": value_clean = False
            
            extracted_inputs.append({
                "name": inp_name,
                "type": py_type,
                "original_type": inp_type,
                "default": value_clean,
                "label": label,
                "category": current_category, # Asignar categoría dinámica
                "options": options
            })
            
        self.inputs = extracted_inputs
        return extracted_inputs

    def parse_set_file(self, content: str) -> Dict[str, Dict[str, Any]]:
        """Parsear contenido de archivo .set de MT5"""
        content = content.lstrip('\ufeff')
        lines = content.split('\n')
        params = {}
        
        for line in lines:
            line = line.strip()
            # Ignore global comments and invalid lines
            if not line or line.startswith(';') or line.startswith('#') or '=' not in line: 
                continue
            
            key, val = line.split('=', 1)
            key = key.strip()
            val = val.strip()
            
            # Clean comments from VALUE if present (e.g. Variable=Value // Comment)
            # Match // or ; but keep track of strings? MT5 .set doesn't обычно put strings with // inside
            val = re.split(r'//|;|#', val)[0].strip()
            
            # Check for Pipe Separated Value (Custom or Specific format)
            if '||' in val:
                parts = val.split('||')
                if len(parts) >= 5:
                    if key not in params: params[key] = {}
                    params[key]['value'] = parts[0].strip()
                    params[key]['start'] = parts[1].strip()
                    params[key]['step'] = parts[2].strip()
                    params[key]['stop'] = parts[3].strip()
                    bg_opt = parts[4].strip().upper()
                    params[key]['opt'] = (bg_opt == 'Y' or bg_opt == 'TRUE' or bg_opt == '1')
                    continue

            # Standard MT5 Modifiers: Name,F (Opt), Name,1 (Start), Name,2 (Step), Name,3 (Stop)
            if ',' in key:
                name, modifier = key.rsplit(',', 1)
                name = name.strip()
                modifier = modifier.strip()
                
                if name not in params: params[name] = {}
                
                if modifier == 'F': 
                    params[name]['opt'] = (val == '1')
                elif modifier == '1': 
                    params[name]['start'] = val
                elif modifier == '2': 
                    params[name]['step'] = val
                elif modifier == '3': 
                    params[name]['stop'] = val
            else:
                # Main value (default)
                name = key
                if name not in params: params[name] = {}
                if 'value' not in params[name]:
                    params[name]['value'] = val
                    
        return params

# Prueba Rápida
if __name__ == "__main__":
    # Test con un archivo dummy si existe
    pass
# Prueba Rápida
if __name__ == "__main__":
    # Mockup
    pass
