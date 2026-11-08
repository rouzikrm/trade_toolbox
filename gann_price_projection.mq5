//+------------------------------------------------------------------+
//|                                           DailyRangeLevels.mq5   |
//|  Draws 6 daily levels derived from the open of the 03:00 candle  |
//+------------------------------------------------------------------+
#property copyright "Daily Range Levels"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6

//--- plot properties
#property indicator_label1  "MidHi"
#property indicator_type1   DRAW_LINE
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "MidLow"
#property indicator_type2   DRAW_LINE
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

#property indicator_label3  "WeakHi"
#property indicator_type3   DRAW_LINE
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

#property indicator_label4  "WeakLow"
#property indicator_type4   DRAW_LINE
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

#property indicator_label5  "ULHi"
#property indicator_type5   DRAW_LINE
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

#property indicator_label6  "ULLow"
#property indicator_type6   DRAW_LINE
#property indicator_style6  STYLE_SOLID
#property indicator_width6  2

//--- inputs
input double UserScale   = 1.0;         // Scale factor (range_open = open * scale)
input double Exponent    = 2.0;         // Power applied to (sqrt(range_open) +/- offset). 3 = your original formula
input bool   DebugPrint  = true;        // Print each day's anchor and levels to the Experts log
input int    StartHour   = 3;           // Anchor candle hour (server time)
input int    StartMinute = 0;           // Anchor candle minute
input int    EndHour     = 23;          // Last drawn hour (server time)
input int    EndMinute   = 30;          // Last drawn minute
input color  MidColor    = clrDodgerBlue;   // Mid levels color
input color  WeakColor   = clrGold;         // Weak levels color
input color  ULColor     = clrTomato;       // UL levels color

//--- buffers
double MidHiBuf[], MidLowBuf[], WeakHiBuf[], WeakLowBuf[], ULHiBuf[], ULLowBuf[];

//--- state
datetime g_anchorDay  = 0;     // day (00:00) for which the anchor is set
double   g_anchorOpen = 0.0;   // open of the anchor candle
datetime g_lastPrintDay = 0;   // debug: last day printed

//+------------------------------------------------------------------+
int OnInit()
  {
   if(UserScale <= 0.0)
     {
      Print("UserScale must be greater than 0");
      return(INIT_PARAMETERS_INCORRECT);
     }

   SetIndexBuffer(0, MidHiBuf,   INDICATOR_DATA);
   SetIndexBuffer(1, MidLowBuf,  INDICATOR_DATA);
   SetIndexBuffer(2, WeakHiBuf,  INDICATOR_DATA);
   SetIndexBuffer(3, WeakLowBuf, INDICATOR_DATA);
   SetIndexBuffer(4, ULHiBuf,    INDICATOR_DATA);
   SetIndexBuffer(5, ULLowBuf,   INDICATOR_DATA);

   color cols[6] = {MidColor, MidColor, WeakColor, WeakColor, ULColor, ULColor};
   for(int i = 0; i < 6; i++)
     {
      PlotIndexSetInteger(i, PLOT_LINE_COLOR, cols[i]);
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);
     }

   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < 1)
      return(0);

   int start;
   if(prev_calculated == 0)
     {
      start        = 0;
      g_anchorDay  = 0;
      g_anchorOpen = 0.0;
     }
   else
      start = prev_calculated - 1;

   const int startSec = StartHour * 3600 + StartMinute * 60;
   const int endSec   = EndHour   * 3600 + EndMinute   * 60;

   for(int i = start; i < rates_total; i++)
     {
      MidHiBuf[i] = MidLowBuf[i] = WeakHiBuf[i] = WeakLowBuf[i] = ULHiBuf[i] = ULLowBuf[i] = EMPTY_VALUE;

      datetime day = time[i] - (time[i] % 86400);
      int      tod = (int)(time[i] % 86400);

      // new day -> forget previous anchor
      if(day != g_anchorDay)
        {
         g_anchorDay  = day;
         g_anchorOpen = 0.0;
        }

      // anchor = open of the 03:00 candle (or first candle at/after it if 03:00 is missing)
      if(g_anchorOpen == 0.0 && tod >= startSec && tod <= endSec)
         g_anchorOpen = open[i];

      if(g_anchorOpen == 0.0 || tod < startSec || tod > endSec)
         continue;

      double rangeOpen = g_anchorOpen * UserScale;
      double priceSqrt = MathSqrt(rangeOpen);

      MidHiBuf[i]   = MathPow(priceSqrt + 0.618, Exponent) / UserScale;
      MidLowBuf[i]  = MathPow(priceSqrt - 0.618, Exponent) / UserScale;
      WeakHiBuf[i]  = MathPow(priceSqrt + 0.382, Exponent) / UserScale;
      WeakLowBuf[i] = MathPow(priceSqrt - 0.382, Exponent) / UserScale;
      ULHiBuf[i]    = MathPow(priceSqrt + (0.618 + 0.382), Exponent) / UserScale;
      ULLowBuf[i]   = MathPow(priceSqrt - (0.618 + 0.382), Exponent) / UserScale;

      if(DebugPrint && g_lastPrintDay != day)
        {
         g_lastPrintDay = day;
         PrintFormat("%s anchor=%.5f midHi=%.5f midLow=%.5f weakHi=%.5f weakLow=%.5f ulHi=%.5f ulLow=%.5f",
                     TimeToString(day, TIME_DATE), g_anchorOpen,
                     MidHiBuf[i], MidLowBuf[i], WeakHiBuf[i], WeakLowBuf[i], ULHiBuf[i], ULLowBuf[i]);
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
