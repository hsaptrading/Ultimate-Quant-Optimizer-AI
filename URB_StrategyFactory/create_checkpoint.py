import shutil
import os
import datetime
import zipfile
import sys

def create_checkpoint(checkpoint_name="Checkpoint"):
    # Root of Project
    project_root = os.getcwd()
    
    # Destination Backup Folder (Outside project if possible, or in dedicated _Backups)
    # Let's put it in "../_URB_Backups" so it doesn't get recursive if I backup project root inside project root
    backup_root = os.path.abspath(os.path.join(project_root, "..", "_URB_Backups"))
    
    if not os.path.exists(backup_root):
        os.makedirs(backup_root)
        
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    safe_name = "".join([c if c.isalnum() else "_" for c in checkpoint_name])
    backup_folder_name = f"{timestamp}_{safe_name}"
    backup_path = os.path.join(backup_root, backup_folder_name) # This will be the zip file base name OR folder

    print(f"Creating checkpoint: {checkpoint_name}...")
    print(f"Source: {project_root}")
    print(f"Destination: {backup_path}.zip")
    
    # Exclude patterns
    # Folders to skip entirely
    SKIP_DIRS = {
        'node_modules', 
        'venv', 
        '.git', 
        '__pycache__', 
        'dist', 
        'build', 
        '.idea', 
        '.vscode',
        'data_cache', # If exists
        'strategies_optimized' # Maybe skip results? Keep for now if small.
    }
    
    # Files to skip
    SKIP_EXTIL = {'.pyc', '.log', '.tmp'}

    try:
        # Create Zip File manually to filter
        zip_filename = f"{backup_path}.zip"
        with zipfile.ZipFile(zip_filename, 'w', zipfile.ZIP_DEFLATED) as zipf:
            for root, dirs, files in os.walk(project_root):
                # Filter Dirs in-place
                dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
                
                for file in files:
                    if any(file.endswith(ext) for ext in SKIP_EXTIL):
                        continue
                        
                    file_path = os.path.join(root, file)
                    # Archive logic: relative path inside zip
                    arcname = os.path.relpath(file_path, project_root)
                    
                    # Avoid archiving the backup itself if it was inside (it's outside now so ok)
                    if "_URB_Backups" in file_path: continue 
                    
                    zipf.write(file_path, arcname)
                    
        print(f"[OK] Checkpoint created successfully: {zip_filename}")
        
    except Exception as e:
        print(f"[ERROR] Error creating checkpoint: {e}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        val = sys.argv[1].strip()
    else:
        print("Enter checkpoint name (default: Manual_Backup): ", end="", flush=True)
        val = sys.stdin.readline().strip()
        
    if not val: val = "Manual_Backup"
    create_checkpoint(val)
