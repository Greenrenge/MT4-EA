#define version "Signal Generator ~ by 7bit ~ V1.0 RC9"

/**
* please change the channel and the nick
* it WON'T WORK with the default ones
*/
extern string server_addr = "64.5.53.69"; // only IP, no domain name!
extern int server_port = 6667;
extern string channel = "#some_channel"; // use your own channel for your signals
extern string nick = "some_nick"; // the nick that this bot will have
extern string website_link = ""; // promote a website. will be sent with account summary.
extern string filter_symbol = ""; // symbol names in uppercase to filter or empty to show all
extern bool show_NAV = false; // show the net asset value (equity) after every line
extern int summary_every_x_hours = 4; // show the summary every x hours
extern bool print_messages_to_log = false; // print all channel messages to the log file

/**
* winsock API (you must allow DLL imports!)
*/
#import "ws2_32.dll"
int WSAGetLastError();
int setsockopt(int socket, int level, int option, int& value[], int len_value);
int socket(int domaint, int type, int protocol);
int connect(int socket, int& address[], int address_len);
int send(int socket, string buffer, int length, int flags);
int inet_addr(string addr); 
#import
#define AF_INET                    2
#define SOCK_STREAM                1
#define SOL_SOCKET                 0xffff
#define SO_SNDTIMEO                0x1005

/**
* cache for all active trades and orders 
* as they were found during the previous tick
*/
int active_ticket[1000];
double active_type[1000];
double active_price[1000];
double active_stoploss[1000];
double active_takeprofit[1000];
bool active_still_active[1000];
int active_total;

/**
* #############################################
* ############# the IRC stuff #################
* #############################################
*/

#define irc_disabled 0 // set to 1 to disable IRC during debugging to avoid z-lines etc.

int s; // socket

/**
* connect to IRC and join channel
*/
void ircconnect(){
   int struct_sockaddr[4];
   int addr, port_low, port_high;
   int opts[1];
   int c;
   
   if (irc_disabled == 1) return(0);
   
   // fill the sockaddr struct
   addr = inet_addr(server_addr);
   port_low = server_port & 0x00ff;
   port_high = (server_port & 0xff00) >> 8; 
   struct_sockaddr[0] = AF_INET | (port_high << 16) | (port_low << 24);
   struct_sockaddr[1] = addr;
   struct_sockaddr[2] = 0;
   struct_sockaddr[3] = 0;
   
   // connect
   s = socket(AF_INET, SOCK_STREAM, 0);
   
   opts[0] = 1000; // send timeout milliseconds
   setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, opts, 4);
   
   c = connect(s, struct_sockaddr, 16);
   Print("connect error: " + WSAGetLastError());
   
   // send some stuff
   Sleep(2000);
   sendLine("user " + nick + " 8 * " + version);
   Sleep(2000);
   sendLine("nick " + nick);
   Sleep(2000);
   sendLine("join " + channel);
   
   Print("handshake error: " + WSAGetLastError());
}

/**
* let the server disconnect by sending sending part and quit
*/
void ircdisconnect(string reason){
   sendLine("part " + channel + " :" + reason);
   sendLine("quit :" + reason);
   s = 0;
}

/**
* this will be called by start()
* every minute. The server won't 
* send us pings then. (at least 
* the unreal ircd at ircforex behaves 
* this way). So we dont need to
* handle any incoming messages at all!
*/
void keepAlive(){
   static int last_time;
   int error;
   if (TimeCurrent() - last_time > 60){
      // send an empty line to the server. This will keep pings away.
      sendLine("");
      error = WSAGetLastError();
      last_time = TimeCurrent();
      if (error != 0){
         // we were disconnected, so reconnect.
         ircconnect();
         message("reconnect after timeout.");
         messageSummary();
      }
   }
}

/**
* send a line of text with newline 
* at the end to the IRC server
*/
void sendLine(string text){
   if (irc_disabled == 1) return(0);
   text = text + CharToStr(13);
   send(s, text, StringLen(text), 0);
}

/**
* send a text message into the channel
*/
void sendChannel(string text){
   sendLine("privmsg " + channel + " :" + text);
}

void sendAction(string text){
   sendChannel(CharToStr(1) + "ACTION " + text + CharToStr(1));
}


/**
* ###################################################
* ############# init, start, deinit #################
* ###################################################
*/

bool stopped = false;
bool restart = true;

int init(){
   
   // default values for debugging.
   // Only used by me and only when debugging
   // and recompiling to set different defaults
   // for me. NEVER EVER use this.
   if (GlobalVariableCheck("this_is_bernds_pc") == true){
      channel = "#livetrades"; // i use this channel for debugging
      nick = "DEMO_bernd";  // i use this nick for debugging
      website_link = "http://prof7bit.mt4stats.com/  (only updated once a week)";
      print_messages_to_log = true;
      show_NAV = true;
   }
   
   // never use default channel and nick
   if (channel == "#some_channel" || nick == "some_nick"){
      label("signal_label1", 10, 15, version);
      label("signal_label2", 10, 30, "please change default channel and nick! *** NOT RUNNING! ***");
      stopped = true;
      return(0);
   }else{
      label("signal_label1", 10, 15, version);
      label("signal_label2", 10, 30, "filter: " + filter_symbol);
      label("signal_label3", 10, 45, "IRC://" + nick + "@" + server_addr + ":" + server_port + "/" + channel);
      ircconnect();
   }
   
   if (UninitializeReason() == REASON_CHARTCHANGE){
      updateActiveOrders();
      restart = false;
   }
}

/**
* called before unload.
* disconnect and clean up.
*/
int deinit(){
   if (UninitializeReason() == REASON_CHARTCHANGE){
      // silently leave the channel
      ircdisconnect("timeframe change");
      return(0);
   }
   
   // send a last friendly word into the channel.
   string text = "Shutting down now";
   switch (UninitializeReason()){
      case REASON_CHARTCLOSE: text = text + " (chart closed). Good Bye!"; break;
      case REASON_PARAMETERS:  text = text + " (parameters changed). Will be back in a bit."; break;
      case REASON_RECOMPILE:  text = text + " (code recompiled). Will be back in a bit."; break;
      case REASON_REMOVE:  text = text + " (EA removed). Good Bye!"; break;
      default:  text = text + ". Good Bye!";
   }
   
   sendAction(text);
   
   // disconnect
   ircdisconnect("EA unload");

   // and we need to clean up the mess in our chart
   ObjectDelete("signal_label1");
   ObjectDelete("signal_label2");
   ObjectDelete("signal_label3");
}


/**
* Main entry point. called by 
* MT4 and will loop forever
* and call start1() every 1 second
*/
int start(){
   while(!IsStopped()){
      start1();
      Sleep(1000);
   }
   return(0);
}

/**
* Main function. called by 
* start once per second
*/
int start1(){
   static datetime time_last_summary;
   double lots;
   
   if(stopped){
      return(0);
   }
   
   RefreshRates();
   
   // we send an empty string to the server
   // every minute to avoid ping timeout 
   keepAlive();
   
   if (restart == true && OrdersTotal() + OrdersHistoryTotal() > 0 && IsConnected()){
      message("Hello traders and bots! This is " + version);
      messageSummary();
      time_last_summary = TimeCurrent();
      updateActiveOrders();
      restart=false;
      return(0);
   }
   
   if (findChanged()){
      updateActiveOrders();
   }
   
   if (time_last_summary == 0){
      time_last_summary = TimeCurrent();
   }
   
   if (TimeCurrent() - time_last_summary > summary_every_x_hours * 3600){
      messageSummary();
      time_last_summary = TimeCurrent();
   }
}



/**
* ##################################################
* ############# message generation #################
* ##################################################
*/

#define O_B_TR  "LONG TRADE  "
#define O_S_TR  "SHORT TRADE "
#define C_B_TR  "CLOSE LONG  "
#define C_S_TR  "CLOSE SHORT "
#define TP_BUY  "* T/P LONG  "
#define SL_BUY  "* S/L LONG  "
#define TP_SEL  "* T/P SHORT "
#define SL_SEL  "* S/L SHORT "
#define O_B_ST  "BUY-STOP    "
#define O_S_ST  "SELL-STOP   "
#define O_B_LI  "BUY-LIMIT   "
#define O_S_LI  "SELL-LIMIT  "
#define C_PEND  "CANCEL      "
#define M_PEND  "MOVE ORDER  "
#define M_STOP  "MOVE S/L    "
#define M_TARG  "MOVE T/P    "
#define F_PEND  "* PENDING ORDER FILLED"


/**
* send the message
*/
void message(string text){
   // we send it via IRC
   sendChannel(text);
   
   // and we also print it to our log
   if (print_messages_to_log == true){
      Print(text);
   }
}

/**
* send the summary (used after restart)
*/
void messageSummary(){
   string text = "";
   int total = OrdersTotal();
   int i, j;
   int type;
   string open_orders_str[];
   int open_orders_ticket[];
   string temp_str;
   int temp_ticket;
   
   message("*** begin account summary ***");
   if (filter_symbol != ""){
      message("filter: " + filter_symbol);
   }
      
   // we want the output nicely sorted by type, symbol and price
   // first we make an array of all order tickets and
   // another one with the strings by which to sort them
   ArrayResize(open_orders_str, total);
   ArrayResize(open_orders_ticket, total);   
   for (i = 0; i < total; i++) {
      OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      
      // make sure that trades will be sorted first, pending second 
      type = OrderType();
      if (type == OP_BUY || type == OP_SELL){
         temp_str = "0";
      }else{
         temp_str = "1";
      }
      
      // we want to have prices in descending
      // order, hence we use (1/price)
      open_orders_str[i] = temp_str + OrderSymbol() + (1 / OrderOpenPrice());
      open_orders_ticket[i] = OrderTicket();      
   }
   
   // now a simple sort algorithm.
   for (i = 0; i < total; i++) {
      for (j = i+1; j < total; j++) {
         if (open_orders_str[i] >= open_orders_str[j]) {
            temp_str = open_orders_str[i];
            open_orders_str[i] = open_orders_str[j];
            open_orders_str[j] = temp_str;
            temp_ticket = open_orders_ticket[i];
            open_orders_ticket[i] = open_orders_ticket[j];
            open_orders_ticket[j] = temp_ticket;
         }
      }
   }
   
   // the tickets in our array are now in the 
   // correct order; we can now simply output them
   for (i = 0; i < total; i++) {
      messageNewOrder(open_orders_ticket[i], True);
   }
   
   // NAV and floating profit
   text = "Floating P/L:" + format(AccountEquity() - AccountBalance(), 2, true);
   if (show_NAV == true){
      text = text + " | Net Asset Value:" + format(AccountEquity(), 2, true);
   }
   
   message(text);
   message("*** end account summary *** " + website_link);
}

/**
* generate a message for a change in an active order 
* this may actually generate and send multiple messages
* for one ticket, one message for every change is sent.
*/
void messageChangedOrder(int index){
   string text = "";
   int ticket = active_ticket[index];
   if (!filter(ticket)){
      return(0);
   }
   
   select(ticket);
   
   // one message for every changed property
   
   // a change of type is a pending order that was filled
   if (active_type[index] != OrderType()){
      text = OrderSymbol6() + " ";
      text = text + F_PEND;
      // two messages: the notification text about the fill and a new open trade message
      message(text);
      messageNewOrder(ticket);
   }
   
   // pending order moved   
   if (active_price[index] != OrderOpenPrice()){
      text = OrderSymbol6() + " ";
      text = text + M_PEND;
      text = text + format(OrderLots()) + " Lot ";
      text = text + " FROM" + format(active_price[index], MarketInfo(OrderSymbol(), MODE_DIGITS)) + " ";
      text = text + " TO" + format(OrderOpenPrice(), MarketInfo(OrderSymbol(), MODE_DIGITS)) + " ";
      addComment(text);
      message(text);
   }
   
   // stoploss
   if (active_stoploss[index] != OrderStopLoss()){
      text = OrderSymbol6() + " ";
      text = text + M_STOP;
      text = text + format(OrderLots()) + " Lot ";
      text = text + "  at" + format(OrderOpenPrice(), MarketInfo(OrderSymbol(), MODE_DIGITS)) + " ";
      text = text + " SL FROM" + format(active_stoploss[index], MarketInfo(OrderSymbol(), MODE_DIGITS)) + " ";
      text = text + " TO" + format(OrderStopLoss(), MarketInfo(OrderSymbol(), MODE_DIGITS)) + " ";
      addComment(text);
      message(text);
   }
   
   // takeprofit
   if (active_takeprofit[index] != OrderTakeProfit()){
      text = OrderSymbol6() + " ";
      text = text + M_TARG;
      text = text + format(OrderLots()) + " Lot ";
      text = text + "  at" + format(OrderOpenPrice(), MarketInfo(OrderSymbol(), MODE_DIGITS)) + " ";
      text = text + " TP FROM" + format(active_takeprofit[index], MarketInfo(OrderSymbol(), MODE_DIGITS)) + " ";
      text = text + " TO" + format(OrderTakeProfit(), MarketInfo(OrderSymbol(), MODE_DIGITS)) + " ";
      addComment(text);
      message(text);
   }
}

/**
* generate a message about a new order 
* and send it.
*/
void messageNewOrder(int ticket, bool profit=False){
   string text = "";
   int type;
   
   if (!filter(ticket)){
      return(0);
   }
   
   select(ticket);
   text = OrderSymbol6() + " ";
   
   type = OrderType();
   if (type == OP_BUY || type == OP_SELL){
      // opened trade
      if (type == OP_BUY){
         text = text + O_B_TR;
      }
      if (type == OP_SELL){
         text = text + O_S_TR;
      }
      text = text + format(OrderLots()) + " Lot ";
      text = text + "from" + format(OrderOpenPrice(), MarketInfo(OrderSymbol(), MODE_DIGITS)) + " ";
   }else{
      // pending order
      if (type == OP_BUYSTOP){
         text = text + O_B_ST;
      }   
      if (type == OP_BUYLIMIT){
         text = text + O_B_LI;
      }   
      if (type == OP_SELLSTOP){
         text = text + O_S_ST;
      }   
      if (type == OP_SELLLIMIT){
         text = text + O_S_LI;
      }   
      text = text + format(OrderLots()) + " Lot ";
      text = text + "  at" + format(OrderOpenPrice(), MarketInfo(OrderSymbol(), MODE_DIGITS)) + " ";
   }
   
   
   if (OrderStopLoss() != 0){
      text = text + " SL:" + format(OrderStopLoss(), MarketInfo(OrderSymbol(), MODE_DIGITS)) + " ";
   }
   
   if (OrderTakeProfit() != 0){
      text = text + " TP:" + format(OrderTakeProfit(), MarketInfo(OrderSymbol(), MODE_DIGITS)) + " ";
   }
   
   // if printing the summary we want to see current P&L for open trades
   if (profit == True && (type == OP_BUY || type == OP_SELL)){
      text = text + " P/L:" + format(OrderProfit() + OrderSwap() + OrderCommission()) + " " + AccountCurrency() + " ";
   }
   
   // if NOT printing the summary we may add the current NAV
   if (profit==false){
      addNAV(text);
   }
   
   addComment(text);
   message(text);
}

/**
* generate a message about a closed order
* and send it.
*/
void messageClosedOrder(int ticket){
   string text = ""; 
   string closed;
   int type;
   double profit;
   
   if (!filter(ticket)){
      return(0);
   }
   
   select(ticket);
   text = OrderSymbol6() + " ";
   type = OrderType();
   
   // closed trade   
   if (type == OP_BUY || type == OP_SELL){
      
      // closed long trade
      if (type == OP_BUY){
         closed = C_B_TR;
         if (wasTP()){
            closed = TP_BUY;
         }
         if (wasSL()){
            closed = SL_BUY;
         }
      }
      
      // closed short trade
      if (type == OP_SELL){
         closed = C_S_TR;
         if (wasTP()){
            closed = TP_SEL;
         }
         if (wasSL()){
            closed = SL_SEL;
         }
      }
      
      text = text + closed;
      text = text + format(OrderLots()) + " Lot ";      
      text = text + "from" + format(OrderOpenPrice(), MarketInfo(OrderSymbol(), MODE_DIGITS)) + " ";
      text = text + "at" + format(OrderClosePrice(), MarketInfo(OrderSymbol(), MODE_DIGITS)) + " ";

      profit = OrderProfit() + OrderSwap() + OrderCommission();
      text = text + "P/L:" + format(profit, 2, true) + " ";

   }
   
   // canceled pending order
   if (type == OP_SELLLIMIT || type == OP_SELLSTOP || type == OP_BUYLIMIT || type == OP_BUYSTOP){
      text = text + C_PEND;
      text = text + format(OrderLots()) + " Lot ";
      text = text + "  at" + format(OrderOpenPrice(), MarketInfo(OrderSymbol(), MODE_DIGITS)) + " ";
   }
   
   addNAV(text);   
   addComment(text);
   message(text);
}

/**
* format a number to a string and add a 
* leading space for positive numbers
*/
string format(double x, int digits=2, bool currency=false){
   string text;
   text = DoubleToStr(x, digits);
   if (x >= 0){
      text = " " + text;
   }
   if (currency == true){
      text = text + " " + AccountCurrency(); 
   }
   return(text);
}

/**
* add the order comment to the message 
*/
void addComment(string &text){
   if (OrderComment() != ""){
      text = text + "(" + OrderComment() + ") ";
   }
}

/**
* add the NAV to the message (if enabled)
*/
void addNAV(string &text){
   if (show_NAV == true){
      text = text + " [NAV:" + format(AccountEquity(), 2, true) + "] ";
   }
}

/**
* was the selected ticket closed by TP?
*/
bool wasTP(){
   if (StringFind(OrderComment(), "[tp]", 0) != -1){
      return(True);
   }else{
      return(false);
   }
}

string OrderSymbol6(){
   return(StringSubstr(OrderSymbol(), 0, 6));
}

/**
* was the selected ticket closed by SL?
*/
bool wasSL(){
   if (StringFind(OrderComment(), "[sl]", 0) != -1){
      return(True);
   }else{
      return(false);
   }
}



/**
* ################################################
* ############# find the changes #################
* ################################################
*/


/**
* find newly opened, changed or closed orders
* and send messages for every change. Additionally
* the function will return true if any changes were
* detected, false otherwise. 
*/
bool findChanged(){
   bool changed = false;
   int total = OrdersTotal();
   int ticket, index;
   for(int i=0; i<total; i++){
      OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      ticket = OrderTicket();
      index = getOrderCacheIndex(ticket);
      if (index == -1){
         // new order
         changed = true;
         messageNewOrder(ticket);
      }else{
         active_still_active[index] = true; // order is still there
         if (OrderOpenPrice() != active_price[index] ||
             OrderStopLoss() != active_stoploss[index] ||
             OrderTakeProfit() != active_takeprofit[index] ||
             OrderType() != active_type[index]){
             // already active order was changed
             changed = true;
             messageChangedOrder(index);
         }
      }
   }
   
   // find closed orders. Orders that are in our cached list 
   // from the last tick but were not seen in the previous step.
   for (index=0; index<active_total; index++){
      if (active_still_active[index] == false){
         // the order must have been closed.
         changed = true;
         messageClosedOrder(active_ticket[index]);
      }
      
      // reset all these temporary flags again for the next tick
      active_still_active[index] = false;
   }
   return(changed);
}

/**
* read in the current state of all open orders 
* and trades so we can track any changes in the next tick
*/ 
void updateActiveOrders(){
   active_total = OrdersTotal();
   for (int i=0; i<active_total; i++){
      OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      active_ticket[i] = OrderTicket();
      active_type[i] = OrderType();
      active_price[i] = OrderOpenPrice();
      active_stoploss[i] = OrderStopLoss();
      active_takeprofit[i] = OrderTakeProfit();
      active_still_active[i] = false; // filled in the next tick
   }
}

/**
* get the index of the ticket in our 
* cached list of open trades
*/
int getOrderCacheIndex(int ticket){
   for (int i=0; i<active_total; i++){
      if (active_ticket[i] == ticket){
         return(i);
      }
   }
   return(-1);
}



/**
* ##############################################
* ############# misc functions #################
* ##############################################
*/

void select(int ticket){
   if (OrderTicket() != ticket){
      OrderSelect(ticket, SELECT_BY_TICKET);
   }
}


/**
* return true if the ticket matches our filter
* so we send only messages for trades we want to share
*/
bool filter(int ticket){
   select(ticket);
   if (filter_symbol=="" || StringFind(filter_symbol, OrderSymbol()) != -1){
      return(true);
   }else{
      return(false);
   }
}


/**
* create the labels on the chart to notify
* the user that this code is running on this chart
*/
void label(string name, int x, int y, string text){
   ObjectCreate(name, OBJ_LABEL, 0, 0, 0);
   ObjectSet(name, OBJPROP_XDISTANCE, x);
   ObjectSet(name, OBJPROP_YDISTANCE, y);
   ObjectSet(name, OBJPROP_CORNER, 2);
   ObjectSetText(name, text);
}