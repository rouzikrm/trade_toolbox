//+------------------------------------------------------------------+
//|                                     MultiSession_ORB_Retest.mq5  |
//|                                  Copyright 2026, MetaTrader 5    |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://www.mql5.com"
#property version   "1.02"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

// --- Input Parameters ---
input group "=== Session Times (HH:MM) ==="
input string   InpSession1Time = "09:00"; // Session 1 Start Time
input string   InpSession2Time = "14:00"; // Session 2 Start Time
input string   InpSession3Time = "20:00"; // Session 3 Start Time
input int      InpORMinutes    = 15;      // Open Range Duration (Minutes)

input group "=== Visual Settings ==="
input color    InpORBoxColor    = clrDodgerBlue; // OR Range Box Color & Line Color
input color    InpBreakoutClr   = clrLimeGreen;  // Bullish Breakout Color
input color    InpBreakoutDnClr = clrCrimson;    // Bearish Breakout Color
input color    InpRetestColor   = clrGold;       // Retest Highlight Color
input bool     InpShowRetests   = true;          // Highlight Retests

// --- Structures ---
struct SessionConfig {
   int  startHour;
   int  startMinute;
   bool active;
};

SessionConfig sessions[3];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   ParseTime(InpSession1Time, sessions[0]);
   ParseTime(InpSession2Time, sessions[1]);
   ParseTime(InpSession3Time, sessions[2]);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "ORB_");
}

//+------------------------------------------------------------------+
//| Parse HH:MM time string into hour and minute                     |
//+------------------------------------------------------------------+
void ParseTime(string timeStr, SessionConfig &cfg)
{
   string parts[];
   if(StringSplit(timeStr, ':', parts) == 2)
   {
      cfg.startHour   = (int)StringToInteger(parts[0]);
      cfg.startMinute = (int)StringToInteger(parts[1]);
      cfg.active      = true;
   }
   else
   {
      cfg.active = false;
   }
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   if(rates_total < 50) return(0);

   // Redraw ORB zones and retests on history update
   DrawSessionORBs(rates_total, time, open, high, low, close);

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Core ORB, Breakout, and Retest Logic                             |
//+------------------------------------------------------------------+
void DrawSessionORBs(int rates_total, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[])
{
   ObjectsDeleteAll(0, "ORB_");

   MqlDateTime dt;
   for(int i = 0; i < rates_total; i++)
   {
      TimeToStruct(time[i], dt);
      
      for(int s = 0; s < 3; s++)
      {
         if(!sessions[s].active) continue;
         
         // Match session start time window
         if(dt.hour == sessions[s].startHour && dt.min >= sessions[s].startMinute && dt.min < (sessions[s].startMinute + InpORMinutes))
         {
            datetime sessionStart = time[i];
            double orHigh = high[i];
            double orLow  = low[i];
            int startIndex = i;
            int endIndex = i;
            
            // Calculate High/Low across the custom duration minutes
            int j = i;
            while(j < rates_total)
            {
               MqlDateTime dtJ;
               TimeToStruct(time[j], dtJ);
               
               long diffMinutes = (time[j] - sessionStart) / 60;
               if(diffMinutes >= 0 && diffMinutes < InpORMinutes && dtJ.day == dt.day)
               {
                  if(high[j] > orHigh) orHigh = high[j];
                  if(low[j] < orLow)   orLow  = low[j];
                  endIndex = j;
                  j++;
               }
               else
               {
                  break;
               }
            }
            
            if(endIndex > startIndex)
            {
               string prefix = StringFormat("ORB_S%d_%s_", s+1, TimeToString(sessionStart, TIME_DATE|TIME_MINUTES));
               
               // 1. Draw Open Range Box for the duration window
               string boxName = prefix + "Box";
               ObjectCreate(0, boxName, OBJ_RECTANGLE, 0, time[startIndex], orHigh, time[endIndex], orLow);
               ObjectSetInteger(0, boxName, OBJPROP_COLOR, InpORBoxColor);
               ObjectSetInteger(0, boxName, OBJPROP_FILL, true);
               ObjectSetInteger(0, boxName, OBJPROP_BACK, true);

               // 2. Extend Upper and Lower Bounds 8 Hours into the Future
               datetime extTime = time[endIndex] + (6 * 3600); // 8 hours in seconds

               string upperLine = prefix + "UpperLine";
               ObjectCreate(0, upperLine, OBJ_TREND, 0, time[startIndex], orHigh, extTime, orHigh);
               ObjectSetInteger(0, upperLine, OBJPROP_COLOR, InpORBoxColor);
               ObjectSetInteger(0, upperLine, OBJPROP_WIDTH, 1);
               ObjectSetInteger(0, upperLine, OBJPROP_STYLE, STYLE_DASH);

               string lowerLine = prefix + "LowerLine";
               ObjectCreate(0, lowerLine, OBJ_TREND, 0, time[startIndex], orLow, extTime, orLow);
               ObjectSetInteger(0, lowerLine, OBJPROP_COLOR, InpORBoxColor);
               ObjectSetInteger(0, lowerLine, OBJPROP_WIDTH, 1);
               ObjectSetInteger(0, lowerLine, OBJPROP_STYLE, STYLE_DASH);

               // 3. Determine session boundary index for the 8-hour extension window
               int sessionEndIndex = endIndex;
               while(sessionEndIndex < rates_total && time[sessionEndIndex] <= extTime)
               {
                  sessionEndIndex++;
               }
               if(sessionEndIndex >= rates_total) sessionEndIndex = rates_total - 1;

               // 4. Scan for Breakout & Retest across the 8-hour window
               bool breakoutUp = false;
               bool breakoutDn = false;
               datetime breakoutTime = 0;
               double breakoutLevel = 0;
               
               for(int k = endIndex + 1; k <= sessionEndIndex; k++)
               {
                  // Bullish Breakout
                  if(!breakoutUp && close[k] > orHigh && open[k] <= orHigh)
                  {
                     breakoutUp = true;
                     breakoutTime = time[k];
                     breakoutLevel = orHigh;
                     
                     string bUpName = prefix + "BreakUp_" + IntegerToString(k);
                     ObjectCreate(0, bUpName, OBJ_ARROW, 0, time[k], high[k]);
                     ObjectSetInteger(0, bUpName, OBJPROP_ARROWCODE, 233); // Arrow Up
                     ObjectSetInteger(0, bUpName, OBJPROP_COLOR, InpBreakoutClr);
                     ObjectSetInteger(0, bUpName, OBJPROP_WIDTH, 2);
                  }
                  
                  // Bearish Breakout
                  if(!breakoutDn && close[k] < orLow && open[k] >= orLow)
                  {
                     breakoutDn = true;
                     breakoutTime = time[k];
                     breakoutLevel = orLow;
                     
                     string bDnName = prefix + "BreakDn_" + IntegerToString(k);
                     ObjectCreate(0, bDnName, OBJ_ARROW, 0, time[k], low[k]);
                     ObjectSetInteger(0, bDnName, OBJPROP_ARROWCODE, 234); // Arrow Down
                     ObjectSetInteger(0, bDnName, OBJPROP_COLOR, InpBreakoutDnClr);
                     ObjectSetInteger(0, bDnName, OBJPROP_WIDTH, 2);
                  }
                  
                  // Retest Detection
                  if(InpShowRetests)
                  {
                     if(breakoutUp && time[k] > breakoutTime)
                     {
                        // Price pulls back to test broken resistance as support
                        if(low[k] <= breakoutLevel && close[k] >= breakoutLevel)
                        {
                           string retestName = prefix + "RetestUp_" + IntegerToString(k);
                           ObjectCreate(0, retestName, OBJ_ARROW, 0, time[k], low[k]);
                           ObjectSetInteger(0, retestName, OBJPROP_ARROWCODE, 159); // Circle marker
                           ObjectSetInteger(0, retestName, OBJPROP_COLOR, InpRetestColor);
                           ObjectSetInteger(0, retestName, OBJPROP_WIDTH, 3);
                           breakoutUp = false; // Reset to log single retest per breakout
                        }
                     }
                     
                     if(breakoutDn && time[k] > breakoutTime)
                     {
                        // Price pulls back to test broken support as resistance
                        if(high[k] >= breakoutLevel && close[k] <= breakoutLevel)
                        {
                           string retestName = prefix + "RetestDn_" + IntegerToString(k);
                           ObjectCreate(0, retestName, OBJ_ARROW, 0, time[k], high[k]);
                           ObjectSetInteger(0, retestName, OBJPROP_ARROWCODE, 159);
                           ObjectSetInteger(0, retestName, OBJPROP_COLOR, InpRetestColor);
                           ObjectSetInteger(0, retestName, OBJPROP_WIDTH, 3);
                           breakoutDn = false;
                        }
                     }
                  }
               }
               
               i = sessionEndIndex; // Skip ahead to next session search
               break;
            }
         }
      }
   }
}
