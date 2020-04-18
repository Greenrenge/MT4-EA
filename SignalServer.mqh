//+------------------------------------------------------------------+
//|                                                 SignalServer.mqh |
//|                                                       Sorasak S. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Sorasak S."
#property link      "https://www.mql5.com"
#property strict
#include "C:/Include/Winsock.mqh"
/*
transactionID | Create,Delete,Edit |OrderInfo|

//recovery
LastTransactionID | Resend |OrderInfo=NULL| *** not kept at any state -- phase II
*/

//|OrderInfo| = [TicketNo|OP_BUY|0.0002|EURUSD|1.12548|1.10000|1.50000|0|12546]

/*
OP_BUY - buy order, 0
OP_SELL - sell order, 1 
OP_BUYLIMIT - buy limit pending order, 2
OP_BUYSTOP - buy stop pending order, 3
OP_SELLLIMIT - sell limit pending order, 4
OP_SELLSTOP - sell stop pending order. 5
*/

/*
ticket number; ****
open time; 
trade operation; ****
amount of lots; ****
symbol; ****
open price; **** 
Stop Loss; ****
Take Profit; ****
close time; 
close price; **** 
commission; 
swap; 
profit; 
comment; 
magic number; ****
pending order expiration date'
*/
class OrderInformation;



class EventTrigger
{
  private:
  string _historyTransaction [][2];
  int LastDispatchTransactionId;
  int _tempReservedHistoryTransactionId;
  int _firstHistoryPosId;
  
  OrderInformation * _orderList[];
  int _historyBufferSize; //buffer size
  int _maxHistoryKept;//no of history to kept for recovering event ( Guarantee)
  
  public:
  EventTrigger(int historyBufferSize,int maxHistoryKept);
  ~EventTrigger();
  void EventTrigger::NewOpenOrderCheck();
  void EventTrigger::CloseCancelOrderCheck();
  int EventTrigger::DispatchEvent(Connection * &  clientArr[]);
  int EventTrigger::ClearHistory();
  //find sell // loop thru order list and check if it is 
  //find buy // user OrderSelect to get an total for looping selectorder and compare with exisiting order list if new = buy, existing must update status of order (takeprofite lvl,stop loss level,pending order exp time,new open price for pending order)
  //keep history
  //Dispatch event
};

void EventTrigger::EventTrigger(int historyBufferSize,int maxHistoryKept)
{
   _historyBufferSize = historyBufferSize;
   _maxHistoryKept = maxHistoryKept;
   //set the base line here
   int currentOrder = OrdersTotal();
   ArrayResize(_orderList, currentOrder);
   for (int i = currentOrder-1;i>=0;i--)
   {
     if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false) continue;
     else 
     {
         /*int tradeTicket = OrderTicket();
         int tradeOperation = OrderType();
         double tradeLot = OrderLots();
         string tradeSymbol = OrderSymbol();
         double tradePrice = OrderOpenPrice();
         double tradeStopLoss = OrderStopLoss();
         double tradeTakeProfit = OrderTakeProfit();
         double tradeClosePrice = OrderClosePrice();
         int tradeMagicNumber = OrderMagicNumber();
         int tradeTicketReference = 0;*/
         _orderList[i] = new OrderInformation(OrderTicket(),OrderType(),OrderLots(),OrderSymbol(),OrderOpenPrice(),OrderStopLoss(),OrderTakeProfit(),OrderClosePrice(),OrderMagicNumber(),0);
     }
   }
   LastDispatchTransactionId = -1; //(HERE : TO GET LastDispatchTransactionId = LastDispatchTransactionId++ after dispatch)
   _tempReservedHistoryTransactionId = LastDispatchTransactionId;
   _firstHistoryPosId = 0;//at first event would later dispatched will have id = 0
   ArrayResize(_historyTransaction,_historyBufferSize);
}

void EventTrigger::~EventTrigger()
{
   int orderCount = ArraySize(_orderList);
   for (int i = orderCount-1;i>=0;i--)
   {
      delete(_orderList[i]);
      _orderList[i] = NULL;
   }
   ArrayResize(_orderList,0);
   ArrayResize(_historyTransaction,0);
}
//caller call checkopen -> checkclose -> (check modify ->) dispatch;
void EventTrigger::NewOpenOrderCheck()
{
   int totalOrder = OrdersTotal();
   int listCount = ArraySize(_orderList);//if we found new order during looping, the new order will not affect the loop iteration
   //looper should call this before close order check
   for (int i = totalOrder-1;i>=0;i--)
   {
     if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false) continue;
     else 
     {
         int tradeTicket = OrderTicket();
         
         bool isNewOrder = true;
         for (int j = listCount-1;j>=0;j--)//TODO:Increase performance
         {
            if(_orderList[j].TradeTicket==tradeTicket)
            {
              isNewOrder = false;
              break;
            }
         }
         
         if(isNewOrder)
         {
           //add new as baseline
           int newSize = ArraySize(_orderList)+1;
           ArrayResize(_orderList,newSize);
           _orderList[newSize-1] = new OrderInformation(OrderTicket(),OrderType(),OrderLots(),OrderSymbol(),OrderOpenPrice(),OrderStopLoss(),OrderTakeProfit(),OrderClosePrice(),OrderMagicNumber(),0);
           
           //create event new and kept in history
           _tempReservedHistoryTransactionId = _tempReservedHistoryTransactionId+1;
           int id = _tempReservedHistoryTransactionId;
           
           
           int historyPlacingIndex = id-_firstHistoryPosId;//_historyBufferSize
           if(historyPlacingIndex > _historyBufferSize-1)
           {
            //exceeding our buffer size
            //resize with reserving some history and set _firstHistoryPosId
            historyPlacingIndex = ClearHistory();
            //set historyPlacingIndex
           }
           _historyTransaction[historyPlacingIndex][0] = IntegerToString(id);
           _historyTransaction[historyPlacingIndex][1] = IntegerToString(id)+ "|C|" + _orderList[newSize-1].ToTransactionString() ;
         }
     }
   }
}
int EventTrigger::ClearHistory()
{
   for(int i = _maxHistoryKept;i > 0 ;i--)
   {
         //moving last [_maxHistoryKept] to first
         _historyTransaction[_maxHistoryKept-i][0] =  _historyTransaction[_historyBufferSize-i][0];
         _historyTransaction[_maxHistoryKept-i][1] =  _historyTransaction[_historyBufferSize-i][1];

   }
   _firstHistoryPosId = _firstHistoryPosId+_historyBufferSize-_maxHistoryKept;//StringToInteger(_historyTransaction[0][0]);
   return _maxHistoryKept;
}
void EventTrigger::CloseCancelOrderCheck()
{
         int listCount = ArraySize(_orderList);
         int CloseList[];// keep index for further remove
         
         for (int j = listCount-1;j>=0;j--)//TODO:Increase performance
         {
            int orderTicket = _orderList[j].TradeTicket;
            //check status of each order 
            
            if(OrderSelect(orderTicket,SELECT_BY_TICKET)==false) continue;
            else
            {
               if(OrderCloseTime()!=0)// open,pending , close time = 0
			      {
               
               int newSize = ArraySize(CloseList)+1;
					ArrayResize(CloseList,newSize);
               CloseList[newSize-1] = j;//keep index of deleted order in orderList array for further remove
					
					//create event new and kept in history
					_tempReservedHistoryTransactionId = _tempReservedHistoryTransactionId+1;
					int id = _tempReservedHistoryTransactionId;// start at zero
					
					 int historyPlacingIndex = id-_firstHistoryPosId;//_historyBufferSize
					 
                if(historyPlacingIndex > _historyBufferSize-1)
                {
                  //exceeding our buffer size
                  //resize with reserving some history and set _firstHistoryPosId
                  historyPlacingIndex = ClearHistory();
                  //set historyPlacingIndex
                }
                _historyTransaction[historyPlacingIndex][0] = IntegerToString(id);
                _historyTransaction[historyPlacingIndex][1] = IntegerToString(id)+ "|D|" + _orderList[j].ToTransactionString() ;
					
				   }
				 }
         }
         // loop thru close list for delete closed order 
         int closeCount = ArraySize(CloseList);
         if(closeCount >0)
         {
           //cliselist must be resort as desc 
/*
[
	0: item A
	1: item B **
	2: item C
	3: item D **
	4" item E
]

[1,3] -- reorder

[3,1] 


[
	0: item A
	1: item B **
	2: item C
	3: item E 
]


[
	0: item A
	1: item E  
	2: item C
]
*/
           ArraySort(CloseList,WHOLE_ARRAY,0,MODE_DESCEND);
           for(int i = 0;i<closeCount;i++)
           {
               RemoveAtIndex(_orderList,CloseList[i]);
           }
           int newOrderListSize = listCount-closeCount;
         }
              
}

int EventTrigger::DispatchEvent(Connection * &  clientArr[])
{
      int countDispatched = 0;
      if(_tempReservedHistoryTransactionId != LastDispatchTransactionId)
      {
         //there is a pending event for dispatching
         for(int i= LastDispatchTransactionId+1;i<=_tempReservedHistoryTransactionId;i++)//
         {
             //Print("LOOKING AT INDEX ",i-_firstHistoryPosId);
             //Print("LOOKING FOR ID ",i);
            if(_historyTransaction[i-_firstHistoryPosId][0] != IntegerToString(i)) 
            {
               Print("ERROR TO TRACK FIRST ELEM ID IN HISTORY ARR");
            }
               //dispatch event
               Print("Dispatching ",_historyTransaction[i-_firstHistoryPosId][1]);
               int clients = ArraySize(clientArr);
               if(clients>0)
               {
                  for(int c = 0; c < clients ; c++)
                  {
                     clientArr[c].SendData(_historyTransaction[i-_firstHistoryPosId][1]);
                  }
               }
               //mark as dispatched
               LastDispatchTransactionId++;
               countDispatched++;
         }
      }
      return countDispatched;
}


//initiated by a transaction
// C will initiate this and is kept in client's array list

class OrderInformation
{

 private:
 
 public:
 int TradeTicket;
 int TradeOperation;
 double TradeLot;
 string TradeSymbol;
 double TradePrice;
 double TradeStopLoss;
 double TradeTakeProfit;
 double TradeClosePrice;
 int TradeMagicNumber;
 int TradeTicketReference;//if client will kept server's ticket here
 
 OrderInformation(int tradeTicket,int tradeOperation,double tradeLot,string tradeSymbol,double tradePrice,double tradeStopLoss,double tradeTakeProfit,double tradeClosePrice,int tradeMagicNumber,int tradeTicketReference);
 ~OrderInformation();
 string ToTransactionString();
 
};
void OrderInformation::OrderInformation(int tradeTicket,int tradeOperation,double tradeLot,string tradeSymbol,double tradePrice,double tradeStopLoss,double tradeTakeProfit,double tradeClosePrice,int tradeMagicNumber,int tradeTicketReference)
{
   TradeTicket =  tradeTicket;
   TradeOperation = tradeOperation;
   TradeLot = tradeLot; 
   TradeSymbol = tradeSymbol;
   TradePrice = tradePrice;
   TradeStopLoss = tradeStopLoss;
   TradeTakeProfit = tradeTakeProfit;
   TradeClosePrice =  tradeClosePrice;
   TradeMagicNumber = tradeMagicNumber;
   TradeTicketReference = tradeTicketReference;
}

void OrderInformation::~OrderInformation()
{

}

string OrderInformation::ToTransactionString()
{
  return IntegerToString(TradeTicket)
         +"|"+IntegerToString(TradeOperation)
         +"|"+DoubleToString(TradeLot)
         +"|"+TradeSymbol
         +"|"+DoubleToString(NormalizeDouble(TradePrice,Digits()))
         +"|"+DoubleToString(NormalizeDouble(TradeStopLoss,Digits()))
         +"|"+DoubleToString(NormalizeDouble(TradeTakeProfit,Digits()))
         +"|"+DoubleToString(NormalizeDouble(TradeClosePrice,Digits()))
         +"|"+IntegerToString(TradeMagicNumber)
         +"|"+IntegerToString(TradeTicketReference);
}

template <typename T> 
void RemoveAtIndex(T& A[], int iPos){
   int iLast = ArraySize(A) - 1;
   delete(A[iPos]);//can we ?
   A[iPos] = A[iLast];
   ArrayResize(A, iLast);
}

template <typename T> void RemoveAtIndexOrdered(T& A[], int iPos){
   for(int iLast = ArraySize(A) - 1; iPos < iLast; ++iPos) 
      A[iPos] = A[iPos + 1];
   ArrayResize(A, iLast);
}