//+------------------------------------------------------------------+
//|  GannSquare.mq5                                                  |
//|  Gann square (fan + arcs) with 5x5 replicas, fixed by date,      |
//|  smart line activation and alerts.                               |
//+------------------------------------------------------------------+
#property version   "1.00"
#property description "Gann square drawn from anchor date/price to end date/price."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

enum ENUM_CF
  {
   CF_ANY     = 0,   // Any candle
   CF_BEARISH = 1,   // Bearish only
   CF_BULLISH = 2    // Bullish only
  };

//--- Square ---------------------------------------------------------
input group "Square"
input datetime InpAnchorTime  = D'2026.01.01 00:00';  // Anchor candle (start, bottom-left)
input datetime InpEndTime     = D'2026.04.01 00:00';  // End candle (right edge, may be in the future)
input double   InpStartPrice  = 0.0;                  // Start price (0 = Low of anchor candle)
input double   InpEndPrice    = 0.0;                  // End price (0 = highest high anchor..end)
input int      InpArcSegments = 24;                   // Arc smoothness (segments per arc)
input color    InpLineColor   = clrWhite;             // Line colour
input color    InpArcColor    = clrWhite;             // Arc colour
input color    InpBorderColor = clrWhite;             // Border colour
input int      InpLineWidth   = 1;                    // Line width

//--- Replicas -------------------------------------------------------
input group "Replicas"
input bool     InpReplicas       = true;                 // Fill with replicas
input int      InpGridN          = 5;                    // Replicas per side (5 = 25 squares)
input color    InpRepLineColor   = C'125,125,125';       // Replica line colour
input color    InpRepArcColor    = C'125,125,125';       // Replica arc colour
input int      InpRepLineWidth   = 1;                    // Replica line width

//--- Smart lines ----------------------------------------------------
input group "Smart lines"
input bool     InpSmart       = true;                 // Highlight activated lines
input bool     InpSupOn       = true;                 // Support test: low < line < close
input ENUM_CF  InpSupFilter   = CF_BEARISH;           // Support test candle type
input bool     InpResOn       = true;                 // Resistance test: high > line > close
input ENUM_CF  InpResFilter   = CF_BULLISH;           // Resistance test candle type
input color    InpSupColor    = clrLime;              // Support activated colour
input color    InpResColor    = clrRed;               // Resistance activated colour
input color    InpBothColor   = clrYellow;            // Both activated colour
input int      InpHlWidth     = 2;                    // Activated line width

//--- Alerts ---------------------------------------------------------
input group "Alerts (fire when a candle closes and activated a line)"
input bool     InpAlertRes    = true;                 // Alert on resistance activation
input bool     InpAlertSup    = false;                // Alert on support activation
input bool     InpPopup       = true;                 // Popup alert
input bool     InpPush        = false;                // Push notification to phone
input bool     InpEmail       = false;                // Send e-mail

//--- Geometry ratios (taken from the picture) -----------------------
double g_top[5]    = {0.125, 0.2, 0.25, 1.0 / 3.0, 0.5};
double g_right[5]  = {0.5, 1.0 / 3.0, 0.25, 0.2, 0.125};
double g_radii[10] = {0.20, 0.28, 0.30, 0.40, 0.445, 0.60, 0.63, 0.80, 0.825, 1.00};

const string PFX = "GannSq_";

//--- One drawn line / arc. Coordinates are (bars from anchor, price). ---
struct SItem
  {
   int    shape;                 // 0 diagonal, 1 steep fan, 2 shallow fan, 3 arc, 4 horizontal, 5 vertical
   double p;                     // ratio / radius
   double ox, oy, cw, ch;        // cell origin and size
   double xa, ya, xb, yb;        // end points (lines only)
   bool   isArc;
   bool   smart;                 // can be tested against candles
   color  baseCol;
   int    baseW;
   int    state;                 // bit 1 = support activated, bit 2 = resistance activated
   string name;
  };

SItem    g_items[];
int      g_n = 0;
MqlRates g_rates[];
int      g_sA = -1;              // shift (bars back) of the anchor candle
double   g_W = 0, g_y0 = 0, g_y1 = 0;
datetime g_lastBar = 0;
bool     g_built = false;

//+------------------------------------------------------------------+
int OnInit()
  {
   ArraySetAsSeries(g_rates, true);
   g_built = false;
   g_lastBar = 0;
   IndicatorSetString(INDICATOR_SHORTNAME, "Gann Square");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
   ChartRedraw();
  }

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[],
                const double &close[], const long &tick_volume[], const long &volume[],
                const int &spread[])
  {
   Update();
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| helpers                                                          |
//+------------------------------------------------------------------+
bool CandleOK(const ENUM_CF f, const double o, const double c)
  {
   if(f == CF_ANY)
      return(true);
   if(f == CF_BEARISH)
      return(c < o);
   return(c > o);
  }

// position of a line inside a unit cell at horizontal fraction u; false if the line does not reach u
bool LevelAt(const int shape, const double p, const double u, double &f)
  {
   switch(shape)
     {
      case 0:
         f = u;
         return(true);
      case 1:
         if(u > p)
            return(false);
         f = u / p;
         return(true);
      case 2:
         f = u * p;
         return(true);
      case 3:
         if(u > p)
            return(false);
         f = MathSqrt(p * p - u * u);
         return(true);
      default:
         f = p;
         return(true);
     }
  }

// first candle at or after time t
int FirstBarAtOrAfter(const datetime t)
  {
   int s = iBarShift(_Symbol, _Period, t, false);
   if(s < 0)
      return(-1);
   if(s > 0 && iTime(_Symbol, _Period, s) < t)
      s--;
   return(s);
  }

// time of a (possibly fractional / negative) bar shift
datetime ShiftToTime(const double s)
  {
   int      ps = PeriodSeconds();
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(s <= 0.0)
      return(t0 + (datetime)MathRound(-s * ps));
   int      lo = (int)MathFloor(s);
   double   fr = s - lo;
   datetime tl = iTime(_Symbol, _Period, lo);
   if(fr <= 0.0)
      return(tl);
   datetime th = iTime(_Symbol, _Period, lo + 1);
   if(th == 0)
      return(tl - (datetime)MathRound(fr * ps));
   return(tl - (datetime)MathRound(fr * (double)(tl - th)));
  }

datetime RelTime(const double t)   // t = bars from anchor
  {
   return(ShiftToTime((double)g_sA - t));
  }

//+------------------------------------------------------------------+
//| smart-line tests                                                 |
//+------------------------------------------------------------------+
// test candle at bars-from-anchor t against one item. returns bit mask 1 = support, 2 = resistance
int TestItemBar(const SItem &it, const int t)
  {
   int s = g_sA - t;
   if(s < 1)                       // closed candles only
      return(0);
   double u = (t - it.ox) / it.cw;
   if(u < 0.0 || u > 1.0)
      return(0);
   double f;
   if(!LevelAt(it.shape, it.p, u, f))
      return(0);
   double lvl = it.oy + it.ch * f;
   int r = 0;
   if(InpSupOn && g_rates[s].low < lvl && g_rates[s].close > lvl &&
      CandleOK(InpSupFilter, g_rates[s].open, g_rates[s].close))
      r |= 1;
   if(InpResOn && g_rates[s].high > lvl && g_rates[s].close < lvl &&
      CandleOK(InpResFilter, g_rates[s].open, g_rates[s].close))
      r |= 2;
   return(r);
  }

int ScanItem(const SItem &it)
  {
   if(!InpSmart || !it.smart)
      return(0);
   int tS = (int)MathMax(0.0, MathCeil(it.ox));
   int tE = (int)MathMin(MathFloor(it.ox + it.cw), (double)(g_sA - 1));
   int st = 0;
   for(int t = tS; t <= tE; t++)
     {
      st |= TestItemBar(it, t);
      if(st == 3)
         break;
     }
   return(st);
  }

//+------------------------------------------------------------------+
//| drawing                                                          |
//+------------------------------------------------------------------+
color StateColor(const SItem &it)
  {
   if(it.state == 3)
      return(InpBothColor);
   if(it.state == 1)
      return(InpSupColor);
   if(it.state == 2)
      return(InpResColor);
   return(it.baseCol);
  }

int StateWidth(const SItem &it)
  {
   return(it.state == 0 ? it.baseW : InpHlWidth);
  }

void MakeTrend(const string nm, const double ta, const double pa, const double tb, const double pb,
               const color col, const int w)
  {
   datetime t1 = RelTime(ta);
   datetime t2 = RelTime(tb);
   if(ObjectFind(0, nm) < 0)
      ObjectCreate(0, nm, OBJ_TREND, 0, t1, pa, t2, pb);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nm, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
  }

void DrawItem(const int i)
  {
   color c = StateColor(g_items[i]);
   int   w = StateWidth(g_items[i]);
   if(!g_items[i].isArc)
     {
      MakeTrend(g_items[i].name, g_items[i].xa, g_items[i].ya, g_items[i].xb, g_items[i].yb, c, w);
      return;
     }
   int    seg = MathMax(4, InpArcSegments);
   double pi2 = M_PI / 2.0;
   for(int k = 0; k < seg; k++)
     {
      double a1 = pi2 * k / seg;
      double a2 = pi2 * (k + 1) / seg;
      double x1 = g_items[i].ox + g_items[i].cw * g_items[i].p * MathCos(a1);
      double y1 = g_items[i].oy + g_items[i].ch * g_items[i].p * MathSin(a1);
      double x2 = g_items[i].ox + g_items[i].cw * g_items[i].p * MathCos(a2);
      double y2 = g_items[i].oy + g_items[i].ch * g_items[i].p * MathSin(a2);
      MakeTrend(g_items[i].name + "_" + IntegerToString(k), x1, y1, x2, y2, c, w);
     }
  }

void StyleItem(const int i)
  {
   color c = StateColor(g_items[i]);
   int   w = StateWidth(g_items[i]);
   if(!g_items[i].isArc)
     {
      ObjectSetInteger(0, g_items[i].name, OBJPROP_COLOR, c);
      ObjectSetInteger(0, g_items[i].name, OBJPROP_WIDTH, w);
      return;
     }
   int seg = MathMax(4, InpArcSegments);
   for(int k = 0; k < seg; k++)
     {
      string nm = g_items[i].name + "_" + IntegerToString(k);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, w);
     }
  }

//+------------------------------------------------------------------+
//| item construction                                                |
//+------------------------------------------------------------------+
void AddItem(const int shape, const double p, const double ox, const double oy, const double cw, const double ch,
             const double xa, const double ya, const double xb, const double yb,
             const bool isArc, const bool smart, const color col, const int w)
  {
   ArrayResize(g_items, g_n + 1);
   g_items[g_n].shape   = shape;
   g_items[g_n].p       = p;
   g_items[g_n].ox      = ox;
   g_items[g_n].oy      = oy;
   g_items[g_n].cw      = cw;
   g_items[g_n].ch      = ch;
   g_items[g_n].xa      = xa;
   g_items[g_n].ya      = ya;
   g_items[g_n].xb      = xb;
   g_items[g_n].yb      = yb;
   g_items[g_n].isArc   = isArc;
   g_items[g_n].smart   = smart;
   g_items[g_n].baseCol = col;
   g_items[g_n].baseW   = w;
   g_items[g_n].state   = 0;
   g_items[g_n].name    = PFX + IntegerToString(g_n);
   g_n++;
  }

// diagonal + fan lines + arcs of one cell
void AddCell(const double ox, const double oy, const double cw, const double ch,
             const color lineCol, const color arcCol, const int w)
  {
   AddItem(0, 0.0, ox, oy, cw, ch, ox, oy, ox + cw, oy + ch, false, true, lineCol, w);
   for(int i = 0; i < 5; i++)
      AddItem(1, g_top[i], ox, oy, cw, ch, ox, oy, ox + cw * g_top[i], oy + ch, false, true, lineCol, w);
   for(int i = 0; i < 5; i++)
      AddItem(2, g_right[i], ox, oy, cw, ch, ox, oy, ox + cw, oy + ch * g_right[i], false, true, lineCol, w);
   for(int i = 0; i < 10; i++)
      AddItem(3, g_radii[i], ox, oy, cw, ch, 0, 0, 0, 0, true, true, arcCol, w);
  }

void BuildItems()
  {
   g_n = 0;
   ArrayResize(g_items, 0);
   double W = g_W, H = g_y1 - g_y0;

   // border: horizontal edges are real price levels, vertical edges are only drawn
   AddItem(4, 0.0, 0, g_y0, W, H, 0, g_y0, W, g_y0, false, true,  InpBorderColor, InpLineWidth);
   AddItem(4, 1.0, 0, g_y0, W, H, 0, g_y1, W, g_y1, false, true,  InpBorderColor, InpLineWidth);
   AddItem(5, 0.0, 0, g_y0, W, H, 0, g_y0, 0, g_y1, false, false, InpBorderColor, InpLineWidth);
   AddItem(5, 0.0, 0, g_y0, W, H, W, g_y0, W, g_y1, false, false, InpBorderColor, InpLineWidth);

   // main square
   AddCell(0, g_y0, W, H, InpLineColor, InpArcColor, InpLineWidth);

   if(InpReplicas)
     {
      int    N  = MathMax(2, InpGridN);
      double cw = W / N, ch = H / N;
      for(int c = 1; c < N; c++)
        {
         AddItem(5, 0.0, 0, g_y0, W, H, cw * c, g_y0, cw * c, g_y1, false, false, InpRepLineColor, InpRepLineWidth);
         AddItem(4, (double)c / N, 0, g_y0, W, H, 0, g_y0 + ch * c, W, g_y0 + ch * c, false, true, InpRepLineColor, InpRepLineWidth);
        }
      for(int cx = 0; cx < N; cx++)
         for(int cy = 0; cy < N; cy++)
            AddCell(cw * cx, g_y0 + ch * cy, cw, ch, InpRepLineColor, InpRepArcColor, InpRepLineWidth);
     }
  }

void Rebuild()
  {
   ObjectsDeleteAll(0, PFX);
   BuildItems();
   for(int i = 0; i < g_n; i++)
     {
      g_items[i].state = ScanItem(g_items[i]);
      DrawItem(i);
     }
  }

// on a new candle: test the candle that just closed, restyle lines that became activated
void IncrementalUpdate()
  {
   if(!InpSmart)
      return;
   int t = g_sA - 1;
   for(int i = 0; i < g_n; i++)
     {
      if(!g_items[i].smart)
         continue;
      int add = TestItemBar(g_items[i], t);
      if((g_items[i].state | add) != g_items[i].state)
        {
         g_items[i].state |= add;
         StyleItem(i);
        }
     }
  }

//+------------------------------------------------------------------+
//| alerts                                                           |
//+------------------------------------------------------------------+
void Notify(const string msg)
  {
   if(InpPopup)
      Alert(msg);
   if(InpPush)
      SendNotification(msg);
   if(InpEmail)
      SendMail("Gann Square", msg);
  }

void CheckAlerts()
  {
   int t = g_sA - 1;
   int nS = 0, nR = 0;
   for(int i = 0; i < g_n; i++)
     {
      if(!g_items[i].smart)
         continue;
      int h = TestItemBar(g_items[i], t);
      if((h & 1) != 0)
         nS++;
      if((h & 2) != 0)
         nR++;
     }
   string tf = StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7);
   string cl = DoubleToString(g_rates[1].close, _Digits);
   if(InpAlertRes && nR > 0)
      Notify(StringFormat("Gann resistance activated on %s (%s) - close %s - %d line(s)", _Symbol, tf, cl, nR));
   if(InpAlertSup && nS > 0)
      Notify(StringFormat("Gann support activated on %s (%s) - close %s - %d line(s)", _Symbol, tf, cl, nS));
  }

//+------------------------------------------------------------------+
//| main update (runs once per new candle)                           |
//+------------------------------------------------------------------+
bool ComputeGeometry(int &sA, int &sEnd, double &y0, double &y1)
  {
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == 0 || InpAnchorTime > t0)
      return(false);
   sA = FirstBarAtOrAfter(InpAnchorTime);
   if(sA < 1)
      return(false);
   int ps = PeriodSeconds();
   if(InpEndTime > t0)
      sEnd = -(int)MathRound((double)(InpEndTime - t0) / ps);   // future end: estimated from the timeframe
   else
      sEnd = FirstBarAtOrAfter(InpEndTime);
   if(sEnd >= sA)
      sEnd = sA - 1;

   y0 = (InpStartPrice != 0.0) ? InpStartPrice : iLow(_Symbol, _Period, sA);
   if(InpEndPrice != 0.0)
      y1 = InpEndPrice;
   else
     {
      int first = MathMax(sEnd, 1);
      int cnt   = sA - first + 1;
      if(cnt < 1)
         return(false);
      int idx = iHighest(_Symbol, _Period, MODE_HIGH, cnt, first);
      if(idx < 0)
         return(false);
      y1 = iHigh(_Symbol, _Period, idx);
     }
   if(MathAbs(y1 - y0) < _Point)
      return(false);
   return(true);
  }

void Update()
  {
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == 0)
      return;
   bool newBar = (t0 != g_lastBar);
   if(g_built && !newBar)
      return;

   int sA, sEnd;
   double y0, y1;
   if(!ComputeGeometry(sA, sEnd, y0, y1))
      return;
   if(CopyRates(_Symbol, _Period, 0, sA + 2, g_rates) < sA + 1)
      return;                                   // history not loaded yet, retry on next tick

   double W = (double)(sA - sEnd);
   bool first = !g_built;
   bool geomChanged = first || MathAbs(W - g_W) > 0.5 ||
                      MathAbs(y0 - g_y0) > _Point / 2.0 || MathAbs(y1 - g_y1) > _Point / 2.0;
   g_sA = sA;
   if(geomChanged)
     {
      g_W = W;
      g_y0 = y0;
      g_y1 = y1;
      Rebuild();
      g_built = true;
     }
   else
      IncrementalUpdate();

   if(!first && newBar)
      CheckAlerts();

   g_lastBar = t0;
   ChartRedraw();
  }
//+------------------------------------------------------------------+
