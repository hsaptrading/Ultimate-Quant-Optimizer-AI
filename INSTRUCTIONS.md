
# 🚀 Cómo encender el sistema URB Strategy Factory

### LAUNCHER SEMI-AUTOMÁTICO
He creado un archivo en tu escritorio llamado **`Start_URB_Factory.bat`**.
Solo haz **doble clic** en él y abrirá todo por ti.

---

### MODO MANUAL (Si el .bat falla)

**Terminal 1: El Cerebro (Backend)**
```powershell
cd "c:\Users\Shakti Ayala\Desktop\URB Optimizer\URB_StrategyFactory\backend"
uvicorn main:app --reload
```
*(Espera a ver "Application startup complete")*

**Terminal 2: La Cara (Frontend)**
```powershell
cd "c:\Users\Shakti Ayala\Desktop\URB Optimizer\URB_StrategyFactory\frontend"
npm run dev
```

---

### 📂 Nota sobre Datos
La App ahora incluye el **Gestor de Datos Dual** (Carpeta vs Subida Manual) y **Selector de Modelado** (M1 vs Tick) en la pestaña "Configuración".
