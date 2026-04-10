//|    UltimateDualPanel.mqh    |
//|   Clase para la gestión del panel visual del EA    |
//|   Versión 4.8 - Solución pragmática para filas vacías    |
//|    |
//+----+
#property strict

#include <ChartObjects/ChartObjectsTxtControls.mqh>
#include <Trade/PositionInfo.mqh>

//--- Paleta de colores actualizada
#define PANEL_MAIN_RECT_BG    C'15,15,25'    // Fondo más oscuro
#define PANEL_BORDER_COLOR    C'102,102,255'    // Borde morado más visible
#define PANEL_SEPARATOR_LIGHT   C'120,120,150'    // Separador principal más claro
#define PANEL_SEPARATOR_DARK    C'80,80,95'    // Separadores secundarios
#define PANEL_TEXT_MAIN    C'255,255,255'    // Texto principal blanco
#define PANEL_TEXT_SECONDARY    C'153,153,255'    // Texto secundario morado claro
#define PANEL_TEXT_VALUE    C'220,220,255'    // Valores de datos más claros
#define PANEL_TEXT_POSITIVE    C'80,200,120'    // Verde para positivo/activo
#define PANEL_TEXT_NEGATIVE    C'255,107,107'    // Rojo para negativo/inactivo
#define PANEL_TEXT_STANDBY    C'255,193,7'    // Amarillo/Ambar para Standby
#define HIGH_IMPACT_COLOR    C'255,0,0'    // Rojo vivo de alto impacto
#define MEDIUM_IMPACT_COLOR    C'60,179,113'    // Verde marino medio (mediumseagreen)
#define PAST_EVENT_COLOR    C'120,120,150'    // Gris más visible para eventos pasados
#define PANEL_TEXT_WARNING    C'255,165,0'    // Naranja para advertencias

//--- Nombres de Objetos
#define MAX_POS_DISPLAY 5
#define MAX_NEWS_DISPLAY 11

//+----+
//| Estructura para los datos de un único evento de noticia    |
//+----+
struct NewsEventData
{
    datetime time;
    string   currency;
    string   name;
    int    importance;
};

//+----+
//| Estructura para pasar el estado del EA al Panel    |
//+----+
struct PanelData
{
    long    magic_number;
    string   news_filter_status;
    string   news_window_info;
    string   trading_session;
    string   correlation_status;
    
    NewsEventData upcoming_events[MAX_NEWS_DISPLAY];
    int    num_upcoming_events;
    
    string   trade_comment;
    string   leverage_info;
    
    double   daily_pl;
    double   daily_pl_pct;
    double   daily_dd;
    double   daily_dd_pct;
    bool    is_pl_dd_calculated;
    
    string   close_on_friday_info;
    string   block_late_friday_info;
    bool    hedging_active;
    string   tp_status_text;
    int    tp_status_state;
    long    tp_status_countdown;
    long    restored_countdown_seconds;
    string   managing_period_info;
    
    string   daily_loss_limit;
    string   total_loss_limit;
    string   daily_profit_limit;
    string   auto_reset_info;
    string   max_account_trades;
    string   max_account_lots;
    
    // Estado del Daily Loss
    bool    daily_loss_reached;
    datetime reset_time;
    string   reset_countdown;
    string   daily_dd_trigger;
    
    bool    consistency_rules_active;
    string   max_profit_per_trade;
    string   max_lot_size_per_trade;
    
    // Nuevo campo para mostrar estado del EA
    bool    ea_stopped_by_daily_loss;
    string   ea_status_message;
    
    // NEW FIELDS FOR v2.68+
    string daily_loss_mode;           // "EA Only" or "All Trades"
    string global_sync_status;        // "Off", "Same Magic", or "All EAs"
    double manual_trades_impact;      // Impact of manual trades today
    bool   show_manual_impact;        // Only show if mode=EA Only and impact!=0
};


//+----+
//| Clase CUltimateDualPanel    |
//+----+
class CUltimateDualPanel
{
private:
    long    m_chart_id;
    int    m_subwin;
    int    m_x;
    int    m_y;
    int    m_width;
    int    m_height;
    string    m_name_prefix;
    
    CPositionInfo    m_pos;
    
    void CreateRectangle(string name, int x, int y, int w, int h, color bg_color, color border_color, int corner = CORNER_LEFT_UPPER, int z_order = 0)
    {
    string obj_name = m_name_prefix + name;
    ObjectCreate(m_chart_id, obj_name, OBJ_RECTANGLE_LABEL, m_subwin, 0, 0);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XSIZE, w);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YSIZE, h);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BGCOLOR, bg_color);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BORDER_COLOR, border_color);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_CORNER, corner);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_ZORDER, z_order);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BACK, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTABLE, false);
    }

    void CreateLabel(string name, int x, int y, string text, color clr, string font = "Calibri", int size = 10, int anchor = ANCHOR_LEFT, int z_order = 1)
    {
    string obj_name = m_name_prefix + name;
    ObjectCreate(m_chart_id, obj_name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_YDISTANCE, y);
    ObjectSetString(m_chart_id, obj_name, OBJPROP_TEXT, text);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_COLOR, clr);
    ObjectSetString(m_chart_id, obj_name, OBJPROP_FONT, font);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_FONTSIZE, size);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_ANCHOR, anchor);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_ZORDER, z_order);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_BACK, false);
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_SELECTABLE, false);
    }
    
    void UpdateLabel(string name, string text, color clr = clrNONE)
    {
    string obj_name = m_name_prefix + name;
    if(ObjectFind(m_chart_id, obj_name) == 0)
    {
    ObjectSetString(m_chart_id, obj_name, OBJPROP_TEXT, text);
    if(clr != clrNONE)
    {
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_COLOR, clr);
    }
    }
    }
    
    //+----+
    //| NUEVA FUNCIÓN: Limpiar completamente un label    |
    //+----+
    void ClearLabel(string name)
    {
        string obj_name = m_name_prefix + name;
        if(ObjectFind(m_chart_id, obj_name) == 0)
        {
            // Doble limpieza para forzar borrado
            ObjectSetString(m_chart_id, obj_name, OBJPROP_TEXT, "");
            ObjectSetInteger(m_chart_id, obj_name, OBJPROP_COLOR, PANEL_MAIN_RECT_BG); // Color de fondo
        }
    }

    void SetLabelFontSize(string name, int size)
    {
        string obj_name = m_name_prefix + name;
        if(ObjectFind(m_chart_id, obj_name) == 0)
        {
            ObjectSetInteger(m_chart_id, obj_name, OBJPROP_FONTSIZE, size);
        }
    }
    
    void HideLabel(string name, bool hide)
    {
    string obj_name = m_name_prefix + name;
    if(ObjectFind(m_chart_id, obj_name) == 0)
    {
    ObjectSetInteger(m_chart_id, obj_name, OBJPROP_HIDDEN, hide);
    }
    }
    
    string TruncateText(string text, int max_length)
    {
    if(StringLen(text) <= max_length) return text;
    return StringSubstr(text, 0, max_length - 3) + "...";
    }
    
    //+----+
    //| NUEVA FUNCIÓN: Validación defensiva de datos de evento    |
    //+----+
    bool IsValidEventData(const NewsEventData &event)
    {
        // Verificar que no sea un "Label" residual o dato vacío
        if(event.currency == "Label" || event.name == "Label")
            return false;
        
        if(event.currency == "" || event.name == "")
            return false;
        
        // Verificar que el timestamp sea válido (no cero ni negativo)
        if(event.time <= 0)
            return false;
        
        // Verificar que la importancia esté en rango válido (1-3)
        if(event.importance < 1 || event.importance > 3)
            return false;
        
        return true;
    }

public:
    CUltimateDualPanel(void) {}
    ~CUltimateDualPanel(void) {}
    
    bool Init(long magic_number, int x=10, int y=40, int w=480, int h=620, int subwin=0)
    {
    m_chart_id = ChartID();
    m_x = x;
    m_y = y;
    m_width = w;
    m_height = h;
    // Ensure enough height for extended events section
    if(m_height < 650) m_height = 650;
    m_subwin = subwin;
    m_name_prefix = "UDP_" + (string)magic_number + "_" + (string)m_chart_id + "_";
    
    ObjectsDeleteAll(m_chart_id, m_name_prefix, 0);
    
    CreateRectangle("MainBorder", m_x, m_y, m_width, m_height, PANEL_BORDER_COLOR, PANEL_BORDER_COLOR, CORNER_LEFT_UPPER, 0);
    CreateRectangle("MainBG", m_x + 1, m_y + 1, m_width - 2, m_height - 2, PANEL_MAIN_RECT_BG, PANEL_MAIN_RECT_BG, CORNER_LEFT_UPPER, 0);
    
    CreateLabel("Title", m_x + (int)(m_width/2), m_y + 21, "ULTIMATE DUAL EA v2.70", PANEL_TEXT_MAIN, "Calibri Bold", 12, ANCHOR_CENTER, 1);
    CreateLabel("StatusLabel", m_x + m_width - 105, m_y + 21, "STATUS:", PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("StatusValue", m_x + m_width - 55, m_y + 21, "ACTIVE", PANEL_TEXT_POSITIVE, "Calibri Bold", 9, ANCHOR_LEFT, 1);
    // Etiqueta de alcance movida a la izquierda del título
    CreateLabel("ScopeTopLabel", m_x + 10, m_y + 21, "SCOPE:", PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("ScopeTopValue", m_x + 50, m_y + 21, "-", PANEL_TEXT_VALUE, "Calibri Bold", 9, ANCHOR_LEFT, 1);
    
    CreateRectangle("HeaderSeparator", m_x + 10, m_y + 40, m_width - 20, 1, PANEL_SEPARATOR_DARK, PANEL_SEPARATOR_DARK, CORNER_LEFT_UPPER, 1);
    
    int card_y = m_y + 55;
    CreateLabel("BalanceLabel", m_x + 10, card_y, "BALANCE", PANEL_TEXT_SECONDARY, "Calibri", 10, ANCHOR_LEFT, 1);
    CreateLabel("BalanceValue", m_x + 10, card_y + 16, "...", PANEL_TEXT_VALUE, "Calibri Bold", 11, ANCHOR_LEFT, 1);
    CreateLabel("PLLabel", m_x + 120, card_y, "DAILY PROFIT", PANEL_TEXT_SECONDARY, "Calibri", 10, ANCHOR_LEFT, 1);
    CreateLabel("PLValue", m_x + 120, card_y + 16, "...", PANEL_TEXT_VALUE, "Calibri Bold", 11, ANCHOR_LEFT, 1);
    CreateLabel("EquityLabel", m_x + 250, card_y, "EQUITY", PANEL_TEXT_SECONDARY, "Calibri", 10, ANCHOR_LEFT, 1);
    CreateLabel("EquityValue", m_x + 250, card_y + 16, "...", PANEL_TEXT_VALUE, "Calibri Bold", 11, ANCHOR_LEFT, 1);
    CreateLabel("DDLabel", m_x + 350, card_y, "DAILY DD", PANEL_TEXT_SECONDARY, "Calibri", 10, ANCHOR_LEFT, 1);
    CreateLabel("DDValue", m_x + 350, card_y + 16, "...", PANEL_TEXT_VALUE, "Calibri Bold", 11, ANCHOR_LEFT, 1);

    CreateRectangle("CardsSeparator", m_x + 10, m_y + 89, m_width - 20, 1, PANEL_SEPARATOR_LIGHT, PANEL_SEPARATOR_LIGHT, CORNER_LEFT_UPPER, 1);

    int pos_y = m_y + 99;
    CreateLabel("PositionsHeader", m_x + 15, pos_y, "OPEN POSITIONS (0)", PANEL_TEXT_MAIN, "Calibri Bold", 10, ANCHOR_LEFT, 1);
    CreateLabel("LeverageLabel", m_x + m_width - 15, pos_y, "Leverage: ...", PANEL_TEXT_MAIN, "Calibri Bold", 9, ANCHOR_RIGHT, 1);
    
    int header_y = pos_y + 20;
    CreateLabel("Col_Sym",    m_x + 20, header_y, "SYMBOL",   PANEL_TEXT_SECONDARY, "Calibri", 10, ANCHOR_LEFT, 1);
    CreateLabel("Col_Type",   m_x + 90, header_y, "TYPE",    PANEL_TEXT_SECONDARY, "Calibri", 10, ANCHOR_LEFT, 1);
    CreateLabel("Col_Vol",    m_x + 140, header_y, "VOLUME",  PANEL_TEXT_SECONDARY, "Calibri", 10, ANCHOR_LEFT, 1);
    CreateLabel("Col_PL",    m_x + 200, header_y, "PROFIT",   PANEL_TEXT_SECONDARY, "Calibri", 10, ANCHOR_LEFT, 1);
    CreateLabel("Col_Comment", m_x + 270, header_y, "STRATEGY", PANEL_TEXT_SECONDARY, "Calibri", 10, ANCHOR_LEFT, 1);

    for(int i=0; i<MAX_POS_DISPLAY; i++)
    {
    int row_y = header_y + 15 + (i*16);
    CreateLabel("Pos_Sym_" +(string)i,  m_x + 20, row_y, "-", PANEL_TEXT_VALUE, "Calibri", 11, ANCHOR_LEFT, 1);
    CreateLabel("Pos_Type_"+(string)i,  m_x + 90, row_y, "-", PANEL_TEXT_VALUE, "Calibri", 11, ANCHOR_LEFT, 1);
    CreateLabel("Pos_Vol_" +(string)i,  m_x + 140,row_y, "-", PANEL_TEXT_VALUE, "Calibri", 11, ANCHOR_LEFT, 1);
    CreateLabel("Pos_PL_"  +(string)i,  m_x + 200,row_y, "-", PANEL_TEXT_VALUE, "Calibri", 11, ANCHOR_LEFT, 1);
    CreateLabel("Pos_Comment_"+(string)i, m_x + 270,row_y, "-", PANEL_TEXT_VALUE, "Calibri", 11, ANCHOR_LEFT, 1);
    }
    
    int filter_separator_y = header_y + 15 + (MAX_POS_DISPLAY * 16) + 5;
    CreateRectangle("PositionsSeparator", m_x + 10, filter_separator_y, m_width - 20, 1, PANEL_SEPARATOR_DARK, PANEL_SEPARATOR_DARK, CORNER_LEFT_UPPER, 1);
    
    int filter_y = filter_separator_y + 12;
    CreateLabel("FilterTitle", m_x + 15, filter_y, "OPERATIONAL FILTERS:", PANEL_TEXT_MAIN, "Calibri Bold", 10, ANCHOR_LEFT, 1);
    
    int filters_row1 = filter_y + 18;
    CreateLabel("FilterNewsLabel",    m_x + 15,  filters_row1, "News:",    PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("FilterNewsValue",    m_x + 50,  filters_row1, "OFF",    PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("FilterTPStatusLabel",  m_x + 15,  filters_row1 + 16, "TP:",   PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("FilterTPStatusValue",  m_x + 35,  filters_row1 + 16, "N/A",    PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);

    CreateLabel("FilterCorrLabel",    m_x + 225, filters_row1, "Corr:",    PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("FilterCorrValue",    m_x + 260, filters_row1, "OFF",    PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("FilterHedgingLabel",   m_x + 350, filters_row1, "Hedging:",   PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("FilterHedgingValue",   m_x + 400, filters_row1, "OFF",    PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);

    int filters_row2_y = filters_row1 + 16;
    CreateLabel("FilterCloseFriLabel", m_x + 225, filters_row2_y, "Close Fri:", PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("FilterCloseFriValue", m_x + 285, filters_row2_y, "OFF",    PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("FilterBlockFriLabel", m_x + 350, filters_row2_y, "Block Fri:", PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("FilterBlockFriValue", m_x + 410, filters_row2_y, "OFF",    PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);

    CreateRectangle("PropSeparator", m_x + 10, filters_row2_y + 25, m_width - 20, 1, PANEL_SEPARATOR_DARK, PANEL_SEPARATOR_DARK, CORNER_LEFT_UPPER, 1);
    
    int prop_y = filters_row2_y + 35;
    CreateLabel("PropTitle", m_x + 15, prop_y, "PROP FIRM SETTINGS:", PANEL_TEXT_MAIN, "Calibri Bold", 10, ANCHOR_LEFT, 1);

    // 3-column layout positions
    int prop_content_width = m_width - 30; // márgenes 15px por lado
    int col_w = prop_content_width / 3;
    int col1_x = m_x + 15;
    int col2_x = col1_x + col_w + 12; // separación extra
    int col3_x = col2_x + col_w + 12; // separación extra
    int row_h = 18; // mayor altura por fila

    // ROW 1: Daily Loss | Total Loss | Daily Profit
    int row1_y = prop_y + 18;
    CreateLabel("DailyLossLabel", col1_x, row1_y, "Daily Loss:", PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("DailyLossValue", col1_x + 60, row1_y, "OFF", PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);

    CreateLabel("TotalLossLabel", col2_x, row1_y, "Total Loss:", PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("TotalLossValue", col2_x + 60, row1_y, "OFF", PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);

    CreateLabel("DailyProfitLabel", col3_x, row1_y, "Daily Profit:", PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("DailyProfitValue", col3_x + 65, row1_y, "OFF", PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);

    // ROW 2: Auto Reset | Max Total Trades | Max Total Lots
    int row2_y = row1_y + row_h;
    CreateLabel("ResetEALabel", col1_x, row2_y, "Auto Reset:", PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("ResetEAValue", col1_x + 65, row2_y, "OFF", PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);

    CreateLabel("MaxTradesLabel", col2_x, row2_y, "Max Total Trades:", PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("MaxTradesValue", col2_x + 100, row2_y, "OFF", PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);

    CreateLabel("MaxLotsLabel", col3_x, row2_y, "Max Total Lots:", PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("MaxLotsValue", col3_x + 85, row2_y, "OFF", PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);

    // No ROW 3: se elimina Manual Trades para una vista más limpia
    int prop_end = row2_y;
    
    CreateRectangle("RulesSeparator", m_x + 10, prop_end + 25, m_width - 20, 1, PANEL_SEPARATOR_DARK, PANEL_SEPARATOR_DARK, CORNER_LEFT_UPPER, 1);
    
    int rules_y = prop_end + 35;
    CreateLabel("RulesTitle", m_x + 15, rules_y, "SPECIAL RULES:", PANEL_TEXT_MAIN, "Calibri Bold", 10, ANCHOR_LEFT, 1);
    
    int rules_row = rules_y + 18;
    CreateLabel("ConsistencyLabel", m_x + 15, rules_row, "Consistency:", PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("ConsistencyValue", m_x + 95, rules_row, "OFF", PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("MaxProfitLabel", m_x + 140, rules_row, "Max Profit/Trade:", PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("MaxProfitValue", m_x + 240, rules_row, "OFF", PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("MaxLotLabel", m_x + 335, rules_row, "Max Lot Per Trade:", PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("MaxLotValue", m_x + 440, rules_row, "OFF", PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);
    
    CreateRectangle("NewsSeparator", m_x + 10, rules_row + 25, m_width - 20, 1, PANEL_SEPARATOR_DARK, PANEL_SEPARATOR_DARK, CORNER_LEFT_UPPER, 1);
    
    int news_y = rules_row + 35;
    CreateLabel("NewsHeader", m_x + 15, news_y, "UPCOMING EVENTS", PANEL_TEXT_MAIN, "Calibri Bold", 11, ANCHOR_LEFT, 1);
    CreateLabel("DateLabel", m_x + (int)(m_width/2), news_y, "...", PANEL_TEXT_MAIN, "Calibri Bold", 9, ANCHOR_CENTER, 1);
    CreateLabel("ClockLabel", m_x + m_width - 15, news_y, "00:00:00", PANEL_TEXT_MAIN, "Calibri Bold", 10, ANCHOR_RIGHT, 1);

    int event_row_y_start = news_y + 22;
    int x_icon = m_x + 20;
    int x_curr = m_x + 40;
    int x_datetime = m_x + 85;
    int x_event = m_x + 210;

    for(int i = 0; i < MAX_NEWS_DISPLAY; i++)
    {
    int row_y = event_row_y_start + (i * 16);
    CreateLabel("News_Icon_" + (string)i, x_icon, row_y, "", clrNONE, "Wingdings", 10, ANCHOR_LEFT, 1);
    CreateLabel("News_Currency_" + (string)i, x_curr, row_y, "", PANEL_TEXT_VALUE, "Calibri Bold", 9, ANCHOR_LEFT, 1);
    CreateLabel("News_DateTime_" + (string)i, x_datetime, row_y, "", PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);
    CreateLabel("News_Event_" + (string)i, x_event, row_y, "", PANEL_TEXT_VALUE, "Calibri", 9, ANCHOR_LEFT, 1);
    }
    
    // Pie de página con aviso legal en esquina inferior derecha
    int footer_y = m_y + m_height - 16; // margen inferior ~16px
    CreateLabel("FooterBrand", m_x + m_width - 15, footer_y, "SA TRADING TOOLS All Rights Reserved", PANEL_TEXT_SECONDARY, "Calibri", 9, ANCHOR_RIGHT, 1);
    
    ChartRedraw(m_chart_id);
    return true;
    }

    void Deinit(const int reason)
    {
    ObjectsDeleteAll(m_chart_id, m_name_prefix, 0);
    ChartRedraw(m_chart_id);
    }

    void Update(PanelData &data)
    {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    UpdateLabel("BalanceValue", "$" + DoubleToString(balance, 2));
    UpdateLabel("EquityValue", "$" + DoubleToString(equity, 2));
    
    // STATUS: ACTIVE (green) until daily loss reached; then INACTIVE (red)
    string status_text = data.daily_loss_reached ? "INACTIVE" : "ACTIVE";
    color status_color = data.daily_loss_reached ? PANEL_TEXT_NEGATIVE : PANEL_TEXT_POSITIVE;
    UpdateLabel("StatusValue", status_text, status_color);
    
    if (data.is_pl_dd_calculated)
    {
    string dd_title = "DAILY DD";
    bool has_trigger = (data.daily_dd_trigger != "");
    if(has_trigger)
    {
        dd_title += " (" + data.daily_dd_trigger + ")";
        SetLabelFontSize("DDLabel", 7);
    }
    else
    {
        SetLabelFontSize("DDLabel", 10);
    }
    color dd_title_color = data.daily_loss_reached ? PANEL_TEXT_NEGATIVE : PANEL_TEXT_SECONDARY;
    UpdateLabel("DDLabel", dd_title, dd_title_color);

    string pl_string = StringFormat("%+.2f (%+.2f%%)", data.daily_pl, data.daily_pl_pct);
    // Daily Profit: white until positive; then green
    color pl_color = (data.daily_pl > 0.0) ? PANEL_TEXT_POSITIVE : PANEL_TEXT_VALUE;
    UpdateLabel("PLValue", pl_string, pl_color);
    
    // Daily Loss display with REACHED indication
    string dd_string;
    color dd_color;
    if(data.daily_loss_reached)
    {
        // Daily DD: show countdown only here
        dd_string = (data.reset_countdown != "") ? ("REACHED (" + data.reset_countdown + ")") : "REACHED";
        dd_color = PANEL_TEXT_NEGATIVE; // red
    }
    else
    {
        // Daily DD: white until >0; then red
        dd_string = (data.daily_dd == 0.0) ? "0.00 (0.00%)" : StringFormat("-%.2f (-%.2f%%)", data.daily_dd, data.daily_dd_pct);
        dd_color = (data.daily_dd > 0.0) ? PANEL_TEXT_NEGATIVE : PANEL_TEXT_VALUE;
    }
    UpdateLabel("DDValue", dd_string, dd_color);
    }
    else
    {
    UpdateLabel("PLValue", "Initializing...", PANEL_TEXT_VALUE);
    UpdateLabel("DDValue", "Initializing...", PANEL_TEXT_VALUE);
    UpdateLabel("DDLabel", "DAILY DD", PANEL_TEXT_SECONDARY);
    SetLabelFontSize("DDLabel", 10);
    }
    
    string current_symbol = Symbol();
    int pos_displayed_count = 0;
    int total_ea_positions = 0;
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
    if(m_pos.SelectByIndex(i) && (long)m_pos.Magic() == data.magic_number)
    {
    total_ea_positions++;
    }
    }
    
    // Pass 1: current symbol, own trades (comment matches this chart)
    for(int i = 0; i < PositionsTotal() && pos_displayed_count < MAX_POS_DISPLAY; i++)
    {
    if(!m_pos.SelectByIndex(i)) continue;
    if((long)m_pos.Magic() != data.magic_number) continue;
    if(m_pos.Symbol() != current_symbol) continue;
    string pos_comment_raw = m_pos.Comment();
    string pos_comment_up = pos_comment_raw; StringToUpper(pos_comment_up);
    string tc_up = data.trade_comment; StringToUpper(tc_up);
    bool is_own = (tc_up == "" || StringFind(pos_comment_up, tc_up) >= 0);
    if(!is_own) continue;

    string type_str = (m_pos.PositionType() == POSITION_TYPE_BUY) ? "BUY" : "SELL";
    color profit_color = (m_pos.Profit() >= 0) ? PANEL_TEXT_POSITIVE : PANEL_TEXT_NEGATIVE;
    color type_color = (type_str == "BUY") ? C'102,153,255' : C'255,102,153';

    UpdateLabel("Pos_Sym_" + (string)pos_displayed_count, m_pos.Symbol());
    UpdateLabel("Pos_Type_" + (string)pos_displayed_count, type_str, type_color);
    UpdateLabel("Pos_Vol_" + (string)pos_displayed_count, DoubleToString(m_pos.Volume(), 2));
    UpdateLabel("Pos_PL_" + (string)pos_displayed_count, StringFormat("%+.2f", m_pos.Profit()), profit_color);

    string comment = pos_comment_raw;
    if(comment == "" && data.trade_comment != "") comment = data.trade_comment;
    if(comment == "") comment = "Default";
    UpdateLabel("Pos_Comment_" + (string)pos_displayed_count, TruncateText(comment, 20));

    pos_displayed_count++;
    }

    // Pass 2: current symbol, other charts (different comment)
    for(int i = 0; i < PositionsTotal() && pos_displayed_count < MAX_POS_DISPLAY; i++)
    {
    if(!m_pos.SelectByIndex(i)) continue;
    if((long)m_pos.Magic() != data.magic_number) continue;
    if(m_pos.Symbol() != current_symbol) continue;
    string pos_comment_raw = m_pos.Comment();
    string pos_comment_up = pos_comment_raw; StringToUpper(pos_comment_up);
    string tc_up = data.trade_comment; StringToUpper(tc_up);
    bool is_own = (tc_up != "" && StringFind(pos_comment_up, tc_up) >= 0);
    if(is_own) continue;

    string type_str = (m_pos.PositionType() == POSITION_TYPE_BUY) ? "BUY" : "SELL";
    color profit_color = (m_pos.Profit() >= 0) ? PANEL_TEXT_POSITIVE : PANEL_TEXT_NEGATIVE;
    color type_color = (type_str == "BUY") ? C'102,153,255' : C'255,102,153';

    UpdateLabel("Pos_Sym_" + (string)pos_displayed_count, m_pos.Symbol());
    UpdateLabel("Pos_Type_" + (string)pos_displayed_count, type_str, type_color);
    UpdateLabel("Pos_Vol_" + (string)pos_displayed_count, DoubleToString(m_pos.Volume(), 2));
    UpdateLabel("Pos_PL_" + (string)pos_displayed_count, StringFormat("%+.2f", m_pos.Profit()), profit_color);

    string comment = pos_comment_raw;
    if(comment == "" && data.trade_comment != "") comment = data.trade_comment;
    if(comment == "") comment = "Default";
    UpdateLabel("Pos_Comment_" + (string)pos_displayed_count, TruncateText(comment, 20));

    pos_displayed_count++;
    }

    // Pass 3: other symbols (existing logic)
    for(int i = 0; i < PositionsTotal() && pos_displayed_count < MAX_POS_DISPLAY; i++)
    {
    if(!m_pos.SelectByIndex(i)) continue;
    if((long)m_pos.Magic() != data.magic_number) continue;
    if(m_pos.Symbol() == current_symbol) continue;

    string type_str = (m_pos.PositionType() == POSITION_TYPE_BUY) ? "BUY" : "SELL";
    color profit_color = (m_pos.Profit() >= 0) ? PANEL_TEXT_POSITIVE : PANEL_TEXT_NEGATIVE;
    color type_color = (type_str == "BUY") ? C'102,153,255' : C'255,102,153';

    UpdateLabel("Pos_Sym_" + (string)pos_displayed_count, m_pos.Symbol());
    UpdateLabel("Pos_Type_" + (string)pos_displayed_count, type_str, type_color);
    UpdateLabel("Pos_Vol_" + (string)pos_displayed_count, DoubleToString(m_pos.Volume(), 2));
    UpdateLabel("Pos_PL_" + (string)pos_displayed_count, StringFormat("%+.2f", m_pos.Profit()), profit_color);

    string comment = m_pos.Comment();
    if(comment == "" && data.trade_comment != "") comment = data.trade_comment;
    if(comment == "") comment = "Default";
    UpdateLabel("Pos_Comment_" + (string)pos_displayed_count, TruncateText(comment, 20));

    pos_displayed_count++;
    }
    
    UpdateLabel("PositionsHeader", "OPEN POSITIONS ("+(string)total_ea_positions+")");
    UpdateLabel("LeverageLabel", data.leverage_info);
    
    for(int i = pos_displayed_count; i < MAX_POS_DISPLAY; i++)
    {
    UpdateLabel("Pos_Sym_" + (string)i, "-");
    UpdateLabel("Pos_Type_" + (string)i, "-", PANEL_TEXT_VALUE);
    UpdateLabel("Pos_Vol_" + (string)i, "-");
    UpdateLabel("Pos_PL_" + (string)i, "-", PANEL_TEXT_VALUE);
    UpdateLabel("Pos_Comment_" + (string)i, "-");
    }

    string news_status = (data.news_filter_status != "OFF") ? data.news_filter_status + data.news_window_info : "OFF";
    color news_color = (data.news_filter_status != "OFF") ? PANEL_TEXT_POSITIVE : PANEL_TEXT_VALUE;
    UpdateLabel("FilterNewsValue", news_status, news_color);
    
    bool is_tp_managed = (data.news_filter_status == "Block & Manage" || data.news_filter_status == "Manage TP");
    
    if(is_tp_managed)
    {
    string countdown_str = "";
    
    switch(data.tp_status_state)
    {
    case 1: // MANAGING
    {
    if(data.tp_status_countdown > 0)
    {
    long minutes = data.tp_status_countdown / 60;
    long seconds = data.tp_status_countdown % 60;
    string period_label = "";
    if(StringFind(data.managing_period_info, "before", 0) >= 0)
    period_label = "BEFORE";
    else if(StringFind(data.managing_period_info, "after", 0) >= 0)
    period_label = "AFTER";
    
    if(period_label != "")
    countdown_str = StringFormat("MANAGING (%s %02d:%02d)", period_label, (int)minutes, (int)seconds);
    else
    countdown_str = StringFormat("MANAGING (%02d:%02d)", (int)minutes, (int)seconds);
    }
    else
    countdown_str = "MANAGING";
    
    UpdateLabel("FilterTPStatusValue", countdown_str, PANEL_TEXT_NEGATIVE);
    break;
    }
    
    case 2: // RESTORED
    {
    if(data.restored_countdown_seconds > 0)
    {
    long minutes = data.restored_countdown_seconds / 60;
    long seconds = data.restored_countdown_seconds % 60;
    countdown_str = StringFormat("RESTORED (%02d:%02d)", (int)minutes, (int)seconds);
    }
    else
    countdown_str = "RESTORED";
    
    UpdateLabel("FilterTPStatusValue", countdown_str, PANEL_TEXT_POSITIVE);
    break;
    }
    
    case 3: // STANDBY
    {
    if(data.tp_status_countdown > 0 && data.tp_status_countdown <= 900)
    {
    long minutes = data.tp_status_countdown / 60;
    long seconds = data.tp_status_countdown % 60;
    countdown_str = StringFormat("STANDBY (%02d:%02d)", (int)minutes, (int)seconds);
    }
    else
    countdown_str = "STANDBY";
    
    UpdateLabel("FilterTPStatusValue", countdown_str, PANEL_TEXT_STANDBY);
    break;
    }
    
    default:
    UpdateLabel("FilterTPStatusValue", "N/A", PANEL_TEXT_VALUE);
    break;
    }
    }
    else
    {
    UpdateLabel("FilterTPStatusValue", "N/A", PANEL_TEXT_VALUE);
    }

    string corr_status = data.correlation_status;
    color corr_color = (corr_status == "OFF") ? PANEL_TEXT_VALUE : PANEL_TEXT_VALUE;
    UpdateLabel("FilterCorrValue", corr_status, corr_color);

    string hedging_status = data.hedging_active ? "ALLOWED" : "BLOCKED";
    color hedging_color = data.hedging_active ? PANEL_TEXT_POSITIVE : PANEL_TEXT_NEGATIVE;
    UpdateLabel("FilterHedgingValue", hedging_status, hedging_color);

    string close_fri_status = data.close_on_friday_info;
    color close_fri_color = (StringFind(close_fri_status, "OFF") < 0) ? PANEL_TEXT_POSITIVE : PANEL_TEXT_VALUE;
    UpdateLabel("FilterCloseFriValue", close_fri_status, close_fri_color);

    string block_fri_status = data.block_late_friday_info;
    color block_fri_color = (StringFind(block_fri_status, "OFF") < 0) ? PANEL_TEXT_POSITIVE : PANEL_TEXT_VALUE;
    UpdateLabel("FilterBlockFriValue", block_fri_status, block_fri_color);

    // Daily Loss Limit: siempre muestra el valor; el color se sincroniza con SCOPE más abajo
    UpdateLabel("DailyLossValue", data.daily_loss_limit, PANEL_TEXT_VALUE);
    
    UpdateLabel("TotalLossValue", data.total_loss_limit, (StringFind(data.total_loss_limit, "OFF") < 0 ? PANEL_TEXT_POSITIVE : PANEL_TEXT_VALUE));
    UpdateLabel("DailyProfitValue", data.daily_profit_limit, (StringFind(data.daily_profit_limit, "OFF") < 0 ? PANEL_TEXT_POSITIVE : PANEL_TEXT_VALUE));
    UpdateLabel("ResetEAValue", data.auto_reset_info, (StringFind(data.auto_reset_info, "OFF") < 0 ? PANEL_TEXT_POSITIVE : PANEL_TEXT_VALUE));
    UpdateLabel("MaxTradesValue", data.max_account_trades, (data.max_account_trades == "OFF" ? PANEL_TEXT_VALUE : PANEL_TEXT_POSITIVE));
    UpdateLabel("MaxLotsValue", data.max_account_lots, (data.max_account_lots == "OFF" ? PANEL_TEXT_VALUE : PANEL_TEXT_POSITIVE));

    // v2.70: Simplificación — SCOPE único y explícito
    // Ocultar elementos redundantes en la tarjeta (Daily Loss Mode / Global Sync)
    HideLabel("DailyLossModeLabel", true);
    HideLabel("DailyLossModeValue", true);
    HideLabel("GlobalSyncLabel", true);
    HideLabel("GlobalSyncValue", true);

    // Encabezado: SCOPE con texto explícito
    string scope_text = "-";
    color scope_color = PANEL_TEXT_VALUE;
    if(StringFind(data.daily_loss_mode, "All Trades") >= 0)
    { scope_text = "ALL TRADES"; scope_color = clrLimeGreen; }
    else if(StringFind(data.daily_loss_mode, "EA Trades (All Charts)") >= 0)
    { scope_text = "ALL EA CHARTS"; scope_color = clrOrange; }
    else if(StringFind(data.daily_loss_mode, "EA Trades (Chart)") >= 0)
    { scope_text = "CHART TRADES"; scope_color = clrDodgerBlue; }
    UpdateLabel("ScopeTopValue", scope_text, scope_color);
    // Recolorear Daily Loss con el color del SCOPE si el límite está activo
    if(StringFind(data.daily_loss_limit, "OFF") < 0)
        UpdateLabel("DailyLossValue", data.daily_loss_limit, scope_color);

    // Manual Trades eliminado del panel (no se muestra)
    
    UpdateLabel("ConsistencyValue", data.consistency_rules_active ? "ON" : "OFF", (data.consistency_rules_active ? PANEL_TEXT_POSITIVE : PANEL_TEXT_VALUE));
    UpdateLabel("MaxProfitValue", data.max_profit_per_trade, (data.max_profit_per_trade == "OFF" ? PANEL_TEXT_VALUE : PANEL_TEXT_POSITIVE));
    UpdateLabel("MaxLotValue", data.max_lot_size_per_trade, (data.max_lot_size_per_trade == "OFF" ? PANEL_TEXT_VALUE : PANEL_TEXT_POSITIVE));

    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    string day_of_week_str = "";
    switch(dt.day_of_week)
    {
    case 0: day_of_week_str = "SUNDAY"; break;
    case 1: day_of_week_str = "MONDAY"; break;
    case 2: day_of_week_str = "TUESDAY"; break;
    case 3: day_of_week_str = "WEDNESDAY"; break;
    case 4: day_of_week_str = "THURSDAY"; break;
    case 5: day_of_week_str = "FRIDAY"; break;
    case 6: day_of_week_str = "SATURDAY"; break;
    }
    string date_str = StringFormat("%s %02i/%02i/%i", day_of_week_str, dt.day, dt.mon, dt.year);
    string time_str = StringFormat("%02i:%02i:%02i", dt.hour, dt.min, dt.sec);
    UpdateLabel("DateLabel", date_str);
    UpdateLabel("ClockLabel", time_str);

    //+----+
    //| SECCIÓN MODIFICADA: Validación defensiva de eventos    |
    //+----+
    int valid_events_displayed = 0;
    
    for(int i = 0; i < MAX_NEWS_DISPLAY; i++)
    {
        // Verificar si hay datos válidos en esta posición
        if(i < data.num_upcoming_events && IsValidEventData(data.upcoming_events[i]))
        {
            // Este evento es válido, mostrarlo
            string icon_char = "";
            color icon_color = clrNONE;
            
            if(data.upcoming_events[i].importance == 3) 
            { 
                icon_char = CharToString(110); // High impact
                icon_color = HIGH_IMPACT_COLOR; 
            }
            else if(data.upcoming_events[i].importance == 2) 
            { 
                icon_char = CharToString(108); // Medium impact
                icon_color = MEDIUM_IMPACT_COLOR; 
            }
            
            string event_datetime = TimeToString(data.upcoming_events[i].time, TIME_DATE|TIME_MINUTES);
            StringReplace(event_datetime, ".", "/");
            string event_name = TruncateText(data.upcoming_events[i].name, 35);

            // Determinar si el evento es pasado
            color text_color = (data.upcoming_events[i].time < TimeCurrent()) ? PAST_EVENT_COLOR : PANEL_TEXT_VALUE;
            color final_icon_color = (data.upcoming_events[i].time < TimeCurrent()) ? PAST_EVENT_COLOR : icon_color;

            // Actualizar labels con los datos del evento válido
            UpdateLabel("News_Icon_" + (string)i, icon_char, final_icon_color);
            UpdateLabel("News_Currency_" + (string)i, data.upcoming_events[i].currency, text_color);
            UpdateLabel("News_DateTime_" + (string)i, event_datetime, text_color);
            UpdateLabel("News_Event_" + (string)i, event_name, text_color);
            
            // Mostrar las filas
            HideLabel("News_Icon_" + (string)i, false);
            HideLabel("News_Currency_" + (string)i, false);
            HideLabel("News_DateTime_" + (string)i, false);
            HideLabel("News_Event_" + (string)i, false);
            
            valid_events_displayed++;
        }
        else
        {
            // Esta fila no tiene datos válidos, limpiarla AGRESIVAMENTE
            ClearLabel("News_Icon_" + (string)i);
            ClearLabel("News_Currency_" + (string)i);
            ClearLabel("News_DateTime_" + (string)i);
            ClearLabel("News_Event_" + (string)i);
            
            // Ahora sí, ocultarlas
            HideLabel("News_Icon_" + (string)i, true);
            HideLabel("News_Currency_" + (string)i, true);
            HideLabel("News_DateTime_" + (string)i, true);
            HideLabel("News_Event_" + (string)i, true);
        }
    }

    ChartRedraw(m_chart_id);
    }
// Recompile
    void OnEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
    {
    }

};



