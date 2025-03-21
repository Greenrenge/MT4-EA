//+------------------------------------------------------------------+
//|                                                    CustomKZM.mq4 |
//|                                                          SORASAK |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+



#property copyright "SORASAK"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#include <StdFunctions.mqh>
//--- input parameters
extern double   ZoneTopGridPrice=1.8;
extern double   ZoneBottomGridPrice=0.7;
extern double   LotSizePerOrder=0.05;
extern int      ZoneMasterSize_Pip=50;
extern int Slippage_Pip = 3;
extern int MagicNumber = 99;
input color ColorZone = clrRed;
input color ColorOpenedZone = clrWhiteSmoke;
//--------------- calculated values
double ZoneArr[][10] ;//[1]=[zoneBasePrice][orderno], max order = 10, return -1 if not use, return 0 if available
int PointsPerPip = getPointsPerPip();
int ZoneTotal = ( NormalizeDouble(ZoneTopGridPrice,Digits) - NormalizeDouble(ZoneBottomGridPrice,Digits)) / NormalizeDouble((ZoneMasterSize_Pip*PointsPerPip*Point),Digits);
string TradeSymbol = Symbol();
double ZoneMasterSize_Point = ZoneMasterSize_Pip*PointsPerPip*Point;
double Slippage_Point = Slippage_Pip*PointsPerPip*Point;

//-----------------------------
//extern bool EnableMultiOrderPerZone = false;
//extern double LotSizePerZone = 0.1;
//ArrayRange(ZoneArr,1)=maximum // lot size per zone will be OrderPerZone*LotSizePerOrder
//MAXIMUM ORDER PER ZONE IS 10
extern int OrderPerZone = 1 ;   
extern int SubMasterSize_Pip = 10;//SubZoneSize in pip (will override tp for zonemaster), use lot per order is LotSizePerOrder
double SubMasterSize_Point = SubMasterSize_Pip *PointsPerPip*Point;

//CONDITION PATRAMETERS BEGIN
//-----------------------------
extern int Condition_HighestLowest_Period = 30; //Highes-Lowest bars to calculate
extern int Condition_HighestLowest_Shift = 10; //Highes-Lowest day shift for stop zone entry
extern int ReTradeAtPercentBTWHiLo = 50;//Percent btw Highest-Lowest for Re-entry
bool DangerousPeriod = false;
double HighestLowestRatio = (ReTradeAtPercentBTWHiLo/ (double) 100) ;



//other info
//double minstoplevel=MarketInfo(Symbol(),MODE_STOPLEVEL);
//--- calculated SL and TP prices must be normalized
//double stoploss=NormalizeDouble(Bid-minstoplevel*Point,Digits);
//double takeprofit=NormalizeDouble(Bid+minstoplevel*Point,Digits);


int OnInit()
  {
  
   //previous zone = start zone 
     /*  TEST
   Print("Point : "+DoubleToString(MarketInfo("USDJPY",MODE_POINT)));
   Print("Digits : "+DoubleToString(MarketInfo("USDJPY",MODE_DIGITS)));
   Print("Lot size : "+DoubleToString(MarketInfo("USDJPY",MODE_LOTSIZE)));
   Print("Lot step : "+DoubleToString(MarketInfo("USDJPY",MODE_LOTSTEP)));
   Print("point per pip :" +IntegerToString(PointsPerPip));*/
   
   //Draw grid zone 
   //Print((ZoneMasterSize_Pip*PointsPerPip*Point));
   Print("TotalZone = " + ZoneTotal);
   //Print("Drawing Zone");
   ArrayResize(ZoneArr,ZoneTotal);
   Print("Toal Array Length : "+ IntegerToString(ArrayRange(ZoneArr,0)));
   
   for(int i_zone=0;i_zone < ZoneTotal;i_zone++)
   {
      /*DrawHorizontalLine("Zone"+IntegerToString(i_zone),ZoneBottomGridPrice+(i_zone*ZoneMasterSize_Point),ColorZone);*/
      //initailize ZoneData
       for(int orderNumber=0;orderNumber<OrderPerZone;orderNumber++)
      {
        ZoneArr[i_zone][orderNumber]= 0;
      }
      for(int orderNumberNotUse=OrderPerZone;orderNumberNotUse<ArrayRange(ZoneArr,1);orderNumberNotUse++)
      {
        ZoneArr[i_zone][orderNumberNotUse]= -1;
      }
   }   
   return(INIT_SUCCEEDED);
  }


void OnDeinit(const int reason)
  {

   
  }

void OnTick()
  {

  
  
      //find zone now
      double price = Ask;
      //Print("Ask : "+DoubleToString(price,5));
      int currentZone = (price-ZoneBottomGridPrice )/(ZoneMasterSize_Point); // < 0 || >ZoneTotal will exceed
      //Print("On Zone : "+IntegerToString(currentZone));
      
      //send price to select what action to do.
      
      //TODO:Check all opened/pending has in this zone already or not
      if(currentZone <= (ZoneTotal -1) && currentZone >= 0)
      {
         //Filtering environment is safty or not
         if(isOkToOpen())
         {
             //if previous zone =
             //if curent zone != previous zone and previous zone is lower than current zone, will buy till xx zone
             if(MathAbs(price - ((currentZone*ZoneMasterSize_Point)+ZoneBottomGridPrice)) < Slippage_Point)
               {
                  OpenOrder(currentZone,currentZone);
               }
         }

      }
      
      /*RenderLowerZoneLine(currentZone);*/
      
      
      
      //will be able to send order which has opened,and pending order to specific zone
      //for(Zone_start to Zone_end)
      //{
      //  logic to select price/lot 
      //}
      
   
  }
  

  
  



int OpenOrder(int startZone,int endZone) // zone start at 10 from bottom to 20 ซื้อรวบโซน
{
   for(int i=startZone;i<=endZone;i++)
   {
      //each zone Zone[i][..]
      //Print("Accessing to Zone["+IntegerToString(i)+"]");
      int countOpenedOrder = 0;
      int trycount = 0;
      for(int orderNumber=0;orderNumber<OrderPerZone;orderNumber++)
      {
         bool isOrderAvailable = false;
         //Print("Accessing to Zone["+IntegerToString(i)+"] : Order["+IntegerToString(orderNumber)+"]");
         if(ZoneArr[i][orderNumber] != 0 && ZoneArr[i][orderNumber]!= -1)
         {
            //have ticket number inside
            if(OrderSelect(ZoneArr[i][orderNumber],SELECT_BY_TICKET)) //order selected from trading pool(opened and pending orders)
            {
               if(OrderMagicNumber() == MagicNumber && OrderCloseTime()==0)
               {
                  //select success this is pending order and opened order
                  //Do what ever you want
                //Print("Zone["+IntegerToString(i)+"] : Order["+IntegerToString(orderNumber)+"] is opened");
                isOrderAvailable = false;
                countOpenedOrder++;
                }
                else //magic number not match and order has been closed
                {
                    ZoneArr[i][orderNumber] = 0;
                    isOrderAvailable = true;
                }
            }
            else
            {
               //Print("[ERROR]Cannot Select Order for Zone["+IntegerToString(i)+"] : Order["+IntegerToString(orderNumber)+"]");
               //Print( "Error Code : "+IntegerToString(GetLastError()));
               ZoneArr[i][orderNumber] = 0;
               isOrderAvailable = true;
            }
         }
         else if(ZoneArr[i][orderNumber] == 0) //ZoneArr[i][orderNumber] == 0 or -1
         {
             isOrderAvailable = true;
         } 
         else//ZoneArr[i][orderNumber] == -1 not use
         {
            isOrderAvailable = false;
         }
         
         if(isOrderAvailable)      
         {
            //openorder
            //Print("Opening Order for Zone["+IntegerToString(i)+"] : Order["+IntegerToString(orderNumber)+"]");
            
            //take profit depends on oderperzone (subZone) but take profit must greater than minimum
            double minTP_SL = NormalizeDouble(MarketInfo(TradeSymbol,MODE_STOPLEVEL)*Point,Digits);//* point?
            /*double takeprofit = NormalizeDouble((((OrderPerZone-orderNumber)*SubMasterSize_Point)+(i)*ZoneMasterSize_Point)+ZoneBottomGridPrice,Digits)*/;//order[0] tp = OrderPerZone*SubMasterSize_Point, order[1] tp = (OrderPerZone-1)*SubMasterSize_Point
            double takeprofit = NormalizeDouble((((ZoneMasterSize_Point)-(orderNumber*SubMasterSize_Point))+(i)*ZoneMasterSize_Point)+ZoneBottomGridPrice,Digits);
            
            
            //No sub zone
            /*double takeprofit = NormalizeDouble(((i+1)*ZoneMasterSize_Point)+ZoneBottomGridPrice,Digits);//tp is exactly next zone only
            double takeprofit = NormalizeDouble(MarketInfo(TradeSymbol,MODE_ASK)+(ZoneMasterSize_Point),Digits);//for flexible tp from buy point*/
            
            //validate takeprofit
            if(takeprofit-MarketInfo(TradeSymbol,MODE_ASK) < minTP_SL)
            {
               //Print("TP is smaller than minimum TP value : "+DoubleToString(minTP_SL));
               takeprofit = MarketInfo(TradeSymbol,MODE_ASK) + minTP_SL;
            }
            
            int ticketResult = OrderSend(TradeSymbol,OP_BUY,LotSizePerOrder,MarketInfo(TradeSymbol,MODE_ASK),Slippage_Pip*PointsPerPip,0,takeprofit,"For Zone : "+IntegerToString(i),MagicNumber,0,clrLightYellow);
            if(ticketResult != -1)
            {
               OpenZone("Zone"+IntegerToString(i),ColorOpenedZone);
               ZoneArr[i][orderNumber] =  ticketResult;
               countOpenedOrder++;
            }
            else 
            {
               //open order fail
               ZoneArr[i][orderNumber] = 0; // set back to available for ZoneArr[i][orderNumber]
               //Print("[ERROR]Cannot OPEN BUY ORDER for Zone["+IntegerToString(i)+"] : Order["+IntegerToString(orderNumber)+"]");
               //Print( "Error Code : "+IntegerToString(GetLastError()));
               
               //Retry open again
               if(trycount < 10)//potential infinite loop, limit try = 10 times
               {
                  orderNumber = orderNumber-1; 
                  trycount++;
               }
               //Print( "Retry sending order for Zone["+IntegerToString(i)+"] : Order["+IntegerToString(orderNumber)+"]");
            }
            
         }
         
      }//end loop order in zone[i]
      if(countOpenedOrder == OrderPerZone)
      {
         //Print("Total order : "+IntegerToString(countOpenedOrder)+" has been opened.");
      }
      
   } //end loop zone
   
   return 0;
}

//FILTERING MARKET FOR ENTRY 
bool isOkToOpen()
{

   double Highest = iCustom(NULL,0,"Highest-Lowest",Condition_HighestLowest_Period,Condition_HighestLowest_Shift,0,0);   
   double Lowest = iCustom(NULL,0,"Highest-Lowest",Condition_HighestLowest_Period,Condition_HighestLowest_Shift,1,0); 
   
   if(Ask < Lowest) 
   { 
      DangerousPeriod = true;
      return false;
   }
   else if(DangerousPeriod)
   {
      Print("now ratio:"+((Ask - Lowest )/(Highest-Lowest)));
      Print("target ratio:"+HighestLowestRatio);
      if(((Ask - Lowest )/(Highest-Lowest)) > HighestLowestRatio) //อยู่สูงกว่ากึ่งกลางระหว่าง high กับ low
      {
         DangerousPeriod = false;
         return true;
      }
      else
      {
         DangerousPeriod = true;
         return false;
          
      }
   }
   else
   {
      DangerousPeriod = false;
      return true;
   }
   
   /*
   double EMA100 = iMA(NULL,0,100,0,MODE_EMA,PRICE_WEIGHTED,0);
   if(Ask < EMA100) return false;
   else return true;*/
}
