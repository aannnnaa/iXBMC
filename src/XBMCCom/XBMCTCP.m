//
//  XBMCTCP.m
//  iXBMC
//
//  Created by Martin Guillon on 5/20/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "XBMCTCP.h"

static XBMCTCP *sharedInstance = nil;

NSString * const kNotification = @"kNotification";
NSString * const kNotificationMessage = @"kNotificationMessage";

@implementation XBMCTCP
@synthesize isRunning = _isRunning;
@synthesize delegate = _delegate;

+ (XBMCTCP *) sharedInstance {
	return ( sharedInstance ? sharedInstance : ( sharedInstance = [[self alloc] init] ) );
}


- (id) init {
    if (!(self = [super init]))
        return nil;
    
    _requestInfos = [NSDictionary dictionary];
    _socket = [[AsyncSocket alloc] initWithDelegate:self];
    [self setIsRunning:NO];
    _notificationCenter = [NSNotificationCenter defaultCenter];
    
    return self;
}

- (void)connect
{
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary* hostinfos = [[defaults objectForKey:@"hosts"] objectForKey:[defaults valueForKey:@"currenthost"]];
    [self connectToHost:[hostinfos objectForKey:@"address"] onPort:[[hostinfos objectForKey:@"tcpport"] integerValue]];
    
}

- (void)connectToHost:(NSString *)hostName onPort:(int)port {
    if (![self isRunning]) {
        if (port < 0 || port > 65535)
            port = 0;
        
        NSError *error = nil;
        if (![_socket connectToHost:hostName onPort:port error:&error]) {
            NSLog(@"Error connecting to server: %@", error);
            return;
        }
        
        [self setIsRunning:YES];
    } else {
        [_socket disconnect];
        [self setIsRunning:false];
    }
}

- (void)disconnect {
    [_socket disconnect];
}

- (void)dealloc {
    [super dealloc];
    [_socket disconnect];
    [_socket dealloc];
    [_requestInfos release];
}

- (void)sendMessage:(NSString *)message withTag:(long)tag{
    NSString *terminatedMessage = [message stringByAppendingString:@"\r\n"];
    NSData *terminatedMessageData = [terminatedMessage dataUsingEncoding:NSASCIIStringEncoding];
    [_socket writeData:terminatedMessageData withTimeout:-1 tag:tag];
}

+ (void)sendMessage:(NSString *)message {
    [[XBMCTCP sharedInstance] sendMessage:message withTag:0];
}

- (void)sendData:(NSData *)data withTag:(long)tag{
    [_socket writeData:data withTimeout:-1 tag:tag];
}

+ (void)sendData:(NSData *)data{
    [[XBMCTCP sharedInstance] sendData:data withTag:0];
}

#pragma mark AsyncSocket Delegate

- (void)onSocket:(AsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port {
    NSLog(@"Connected to server %@:%hu", host, port);
    [sock readDataToData:[AsyncSocket LFData] withTimeout:-1 tag:0];
    if ([[self delegate] respondsToSelector:@selector(XBMCTCPConnected)])
    {
        [[self delegate] XBMCTCPConnected];
    }
//    [self sendMessage:@"{\"jsonrpc\": \"2.0\", \"method\": \"JSONRPC.Introspect\", \"id\": \"1\"}"];
}

- (void)onSocket:(AsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    NSData *truncatedData = [data subdataWithRange:NSMakeRange(0, [data length] - 1)];
//    NSString *message = [[[NSString alloc] initWithData:truncatedData encoding:NSASCIIStringEncoding] autorelease];
    NSString * requestId = [NSString stringWithFormat:@"%d",tag];
    
//    if (message)
//        NSLog(@"%@", message);
//    else
//        NSLog(@"Error converting received data into UTF-8 String");
//
//    
    
    NSError *error = nil;
    NSArray *results = [truncatedData yajl_JSONWithOptions:YAJLParserOptionsAllowComments error:&error];
    // 	NSLog(@"json %@",results);    
	// Handle parse error
	if(error) {
		[sock readDataToData:[AsyncSocket LFData] withTimeout:-1 tag:0];
        return;
	}
    for (NSDictionary *result in results)
    {
        
        NSDictionary *resultDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithBool:([result objectForKey:@"error"] != [NSNull null])], @"failure", 
                                    requestId, @"request", 
                                    [result objectForKey:@"result"], @"result",
                                    [[_requestInfos objectForKey:requestId] objectForKey:@"info"], @"info",nil];
        id <NSObject> obj = [[_requestInfos objectForKey:requestId] objectForKey:@"object"];
        if (obj) {
            SEL aSel = [[[_requestInfos objectForKey:requestId] objectForKey:@"selector"] pointerValue];
            if ([obj respondsToSelector:aSel])
                [obj performSelector:aSel withObject:resultDict];
        }
    }
//    else
//    {
//        if ([[self delegate] respondsToSelector:@selector(XBMCTCPReceivedData:)])
//        {
//            [[self delegate] XBMCTCPReceivedData:dictionary];
//        } 
//    }
    
//    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:message forKey:kNotificationMessage];
//    [_notificationCenter postNotificationName:kNotification object:self userInfo:userInfo];
//    
    [sock readDataToData:[AsyncSocket LFData] withTimeout:-1 tag:0];
}

- (void)onSocket:(AsyncSocket *)sock didWriteDataWithTag:(long)tag {
    [sock readDataToData:[AsyncSocket LFData] withTimeout:-1 tag:0];
}

- (void)onSocket:(AsyncSocket *)sock willDisconnectWithError:(NSError *)err {
    NSLog(@"Client Disconnected: %@:%hu", [sock connectedHost], [sock connectedPort]);
    // Let the delegate know, so it can try to recover if it likes.
    if ([[self delegate] respondsToSelector:@selector(XBMCTCPDisconnected)])
    {
        [[self delegate] XBMCTCPDisconnected];
    }
}



- (void)JSONRequest:(NSString *)method 
                   params:(NSObject *)params 
                     info:(NSDictionary *)info 
                   target:(NSObject*)object 
                 selector:(SEL)sel
{
    NSArray *jsonRpc = [NSDictionary dictionaryWithObjectsAndKeys:
						@"2.0", @"jsonrpc",
						method, @"method",
						params, @"params",
						@"1", @"id",
						nil];
    
//	NSData *serialized = [jsonRpc JSONData];
    NSString *string = [jsonRpc yajl_JSONString];
    NSLog(@"sending %@", string);
	NSData *serializedData = [string dataUsingEncoding:NSUTF8StringEncoding];
    
    NSInteger requestId = (int)[[NSDate date] timeIntervalSince1970]*100;
    NSDictionary* tag = [NSDictionary dictionaryWithObjectsAndKeys:
                          info?info:[NSDictionary dictionary], @"info",
                          method, @"cmd",
                          object, @"object",
                          [NSValue valueWithPointer:sel], @"selector",
                          nil];
    
    [_requestInfos setValue:tag forKey:[NSString stringWithFormat:@"%d",requestId]];
    
    [self sendData:serializedData withTag:requestId];
    
    //    [serialized release];
}

-(void)JSONRequest:(NSDictionary*)rq target:(NSObject*)object selector:(SEL)sel 
{
    [self JSONRequest:[rq objectForKey:@"cmd"] 
                         params:[rq objectForKey:@"params"]
                           info:[rq objectForKey:@"info"]
                         target:object selector:sel];
}


-(void)addJSONRequest:(NSDictionary*)rq 
{
    [self JSONRequest:rq target:nil selector:nil];
}

@end
