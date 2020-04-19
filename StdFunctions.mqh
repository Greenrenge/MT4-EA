//+------------------------------------------------------------------+
//|                                                 StdFunctions.mqh |
//|                                                          SORASAK |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "SORASAK"
#property link      "https://www.mql5.com"
#property strict

int getPointsPerPip()
{
   if(MarketInfo(Symbol(), MODE_DIGITS)==3||MarketInfo(Symbol(), MODE_DIGITS)==5)
   {
      return 10;
   }
   else 
   {
      return 1;
   }
}
void DrawHorizontalLine(string LineName, double price,color Color)
   {  
   ObjectDelete(LineName);
   price = NormalizeDouble(price,5);
   ObjectCreate(LineName, OBJ_HLINE,0,0,price);
   ObjectSet(LineName, OBJPROP_STYLE, STYLE_SOLID );
   ObjectSet(LineName, OBJPROP_WIDTH, 1);
   ObjectSet(LineName, OBJPROP_COLOR,Color);
   }
   
void OpenZone(string LineName,color Color)
{
   ObjectSet(LineName,OBJPROP_COLOR,Color);
}
 void CloseZone(string LineName,color Color)
{
  ObjectSet(LineName,OBJPROP_COLOR,Color);
}

//+------------------------------------------------------------------+
//| defines                                                          |
//+------------------------------------------------------------------+
// #define MacrosHello   "Hello, world!"
// #define MacrosYear    2010
//+------------------------------------------------------------------+
//| DLL imports                                                      |
//+------------------------------------------------------------------+
// #import "user32.dll"
//   int      SendMessageA(int hWnd,int Msg,int wParam,int lParam);
// #import "my_expert.dll"
//   int      ExpertRecalculate(int wParam,int lParam);
// #import
//+------------------------------------------------------------------+
//| EX5 imports                                                      |
//+------------------------------------------------------------------+
// #import "stdlib.ex5"
//   string ErrorDescription(int error_code);
// #import
//+------------------------------------------------------------------+
