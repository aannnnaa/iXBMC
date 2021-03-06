#import "DetailViewController.h"
#import "ActiveManager.h"
#import "DetailView.h"

#import "Movie.h"
#import "ActorRole.h"
#import "Actor.h"

#import "XBMCStateListener.h"
#import "XBMCCommand.h"
#import "XBMCImage.h"

#import "CustomTitleView.h"

#import "FadingImageView.h"


@implementation DetailViewController
@synthesize details = _details;


#pragma mark - View lifecycle

-(id) initWithNavigatorURL:(NSURL*)URL query:(NSDictionary*)query
//- (id)initWithEntity:(NSString *)entity id:(NSString *)entityId 
{
    self = [super init];
    if (self)
    {		
		self.view.backgroundColor = TTSTYLEVAR(detailsViewBackColor);
        
		////toolbar
		_toolBar = [self createToolbar];
		[self.view addSubview:_toolBar];
		
		_titleBackground = [[[CustomTitleView alloc] init] retain];
		[_titleBackground addTarget:self action:@selector(toggleToolbar) forControlEvents:UIControlEventTouchUpInside];
		
		self.navigationItem.titleView = _titleBackground;
		
		UISwipeGestureRecognizer* recognizer = [[UISwipeGestureRecognizer alloc] 
												initWithTarget:self 
												action:@selector(handleSwipe:)];
		recognizer.direction = UISwipeGestureRecognizerDirectionRight;
		[self.view addGestureRecognizer:recognizer];
		[recognizer release];
		
		self.details = [NSMutableDictionary dictionaryWithDictionary:query];
		_start = [[NSDate date] retain];
		if ([_details objectForKey:@"type"])
		{
			if ([[_details valueForKey:@"type"] isEqualToString:@"movie"])
			{
				if ([_details objectForKey:@"id"])
				{
					NSArray *array = [[[ActiveManager shared] managedObjectContext] fetchObjectsForEntityName:@"Movie" withPredicate:
									  [NSPredicate predicateWithFormat:@"movieid == %@", [_details valueForKey:@"id"]]];
					
					if (array == nil || [array count] ==0) {
						TTErrorView* errorView = [[[TTErrorView alloc] initWithTitle:@"Error"
																			subtitle:@"Could not find item in Database"
																			   image:TTIMAGE(@"bundle://error.png")] 
												  autorelease];
						errorView.backgroundColor = RGBCOLOR(0, 0, 0);
						self.view = errorView;
						return self;
					}
					Movie* movie = (Movie*)[array objectAtIndex:0];
					[_details setValue:movie.label forKey:@"label"];
					[_details setValue:movie.file forKey:@"fileURL"];
					[_details setValue:movie.trailer forKey:@"trailerURL"];
					[_details setValue:movie.imdbid forKey:@"imdb"];
					[_details setValue:movie.thumbnail forKey:@"coverURL"];
					[_details setValue:movie.fanart forKey:@"fanartURL"];
					[_details setValue:[NSNumber numberWithBool:([movie.playcount intValue] != 0)] forKey:@"watched"];
					[_details setValue:movie.rating forKey:@"rating"];
					[_details setValue:movie.director forKey:@"director"];
					[_details setValue:movie.writer forKey:@"writer"];
					[_details setValue:movie.year forKey:@"year"];
					[_details setValue:movie.runtime forKey:@"runtime"];
					[_details setValue:movie.genre forKey:@"genre"];
					[_details setValue:movie.plot forKey:@"plot"];
					NSMutableDictionary* cast = [NSMutableDictionary dictionary];
					for (ActorRole* role in movie.roles)
					{
						if (![role.role isEqualToString:@""])
							[cast setValue:role.actorName forKey:role.role];
					}
					[_details setValue:cast forKey:@"cast"];
				}
				else
				{
					
				}
				[self updateViewForMovie];
			}
		}
		else
		{
			TTErrorView* errorView = [[[TTErrorView alloc] initWithTitle:@"Error"
                                                                subtitle:@"Could not find item in Database"
                                                                   image:TTIMAGE(@"bundle://error.png")] 
                                      autorelease];
            errorView.backgroundColor = RGBCOLOR(0, 0, 0);
            self.view = errorView;
            return self;
		}
    }
    return self ;
}

- (void)dealloc {
    TT_RELEASE_SAFELY(_start);
    TT_RELEASE_SAFELY(_toolbarButtons);
    TT_RELEASE_SAFELY(_titleBackground);
    
	[super dealloc];
}

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad
{    
	[super viewDidLoad];
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	
	[center
     addObserver:self
     selector:@selector(disconnectedFromXBMC:)
     name:@"DisconnectedFromXBMC"
     object:nil ];
}


- (void)viewDidUnload
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super viewDidUnload];
}

- (void)viewWillAppear:(BOOL)animated 
{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	NSLog(@"time took: %f", -[_start timeIntervalSinceNow]);
	
	if (_detailView) return;
		
	_detailView = [[[DetailView alloc] init] autorelease];
	_detailView.frame  = self.view.frame;
	_detailView.alpha = 0.0;
	[self.view insertSubview:_detailView belowSubview:_toolBar];

	[_detailView setInfo:[_details valueForKey:@"formatedInfo"]];
	[_detailView setPlot:[_details valueForKey:@"formatedPlot"]];
	[_detailView setCast:[_details valueForKey:@"formatedCast"]];

	if (![[_details valueForKey:@"watched"] boolValue])
	{
		_detailView.newFlag.hidden = FALSE;
	}
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([_details objectForKey:@"coverURL"])
	{
		CGFloat height = TTSTYLEVAR(movieDetailsViewCoverHeight);
		if ([[defaults valueForKey:@"images:highQuality"] boolValue])
		{
			height *= (CGFloat)TTSTYLEVAR(highQualityFactor);
		}
		UITapGestureRecognizer *tapgr = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapCover:)];
		[_detailView.cover addGestureRecognizer:tapgr];
		[tapgr release];    
		[XBMCImage askForImage:[_details valueForKey:@"coverURL"] 
						object:self selector:@selector(coverLoaded:) 
				 thumbnailHeight:height];
	}
	
	if ([_details objectForKey:@"fanartURL"])
	{
		NSInteger fanartHeight = TTScreenBounds().size.height;
		if ([[defaults valueForKey:@"images:highQuality"] boolValue])
		{
			fanartHeight *= (CGFloat)TTSTYLEVAR(highQualityFactor);
		}
		[XBMCImage askForImage:[_details valueForKey:@"fanartURL"] 
						object:self selector:@selector(fanartLoaded:) 
				 thumbnailHeight:fanartHeight];
	}
	
	[UIView beginAnimations:nil context:_detailView];
    [UIView setAnimationDuration:0.2];
	_detailView.alpha = 1.0;
    [UIView commitAnimations];

}

- (void)updateViewForMovie
{
	NSString* infoText = @"";
	if ([_details valueForKey:@"director"])
	{
		infoText = [infoText stringByAppendingFormat:@"\
					<span class=\"grayText\">Director:</span>\n\
					<span class=\"whiteText\">%@</span>\n\n", [_details valueForKey:@"director"]]; 
	}
	if ([_details valueForKey:@"writer"])
	{
		infoText = [infoText stringByAppendingFormat:@"\
					<span class=\"grayText\">Writer:</span>\n\
					<span class=\"whiteText\">%@</span>\n\n", [_details valueForKey:@"writer"]]; 
	}
	if ([[_details valueForKey:@"year"] integerValue] != 0)
	{
		infoText = [infoText stringByAppendingFormat:@"\
					<span class=\"grayText\">Year:</span>\n\
					<span class=\"whiteText\">%@</span>\n\n", [[_details valueForKey:@"year"] stringValue]]; 
	}
	if ([_details valueForKey:@"runtime"])
	{
		NSString* runtime = [NSString stringWithString:[_details valueForKey:@"runtime"]];
		NSRange foundRange = [runtime rangeOfString:@"min"];
		
		if ((foundRange.length == 0) ||
			(foundRange.location == 0))
		{
			runtime = [runtime stringByAppendingString:@" min"];
		}
		infoText = [infoText stringByAppendingFormat:@"\
					<span class=\"grayText\">Runtime:</span>\n\
					<span class=\"whiteText\">%@</span>\n\n", runtime]; 
	}
	//        if ([movie.rating floatValue] != 0.0)
	{            
		infoText = [infoText stringByAppendingFormat:@"\
					<span class=\"grayText\">Imdb Rating: </span>\
					<img src=\"bundle://star.%.1f.png\" width=\"100\" height=\"20\"/>\n\n"
					, [[_details valueForKey:@"rating"] floatValue]]; 
		//            <span class=\"whiteText\">%.1f</span>\n\n", [movie.rating floatValue]]; 
	}
	
	[_details setValue:infoText forKey:@"formatedInfo"];
//	self.info = infoText;
	
	NSString* plotText = @"";
	if ([_details valueForKey:@"plot"])
	{
		plotText = [plotText stringByAppendingFormat:@"\
					<span class=\"whiteText\">%@</span>\n\n", [_details valueForKey:@"plot"]]; 
	}
//	self.plot = plotText;
	[_details setValue:plotText forKey:@"formatedPlot"];
	
	
	///ACTORS
	if ([_details objectForKey:@"cast"])
	{
		NSString* castText = @"";
		for (NSString* key in [_details objectForKey:@"cast"])
		{
			//            NSLog(@"role: %@ - %@", role.RoleToActor.name, role.role);
			castText = [castText stringByAppendingFormat:@"\
						<img src=\"bundle://defaultPerson.png\" width=\"25\" height=\"25\"/>\
						<span class=\"whiteText\">  %@ </span>\
						<span class=\"grayText\">  %@</span>\n\n"
						, [[_details objectForKey:@"cast"] valueForKey:key], key]; 
		}
//		self.cast = castText;
		[_details setValue:castText forKey:@"formatedCast"];
	}
	
	_titleBackground.title = [_details valueForKey:@"label"];
	_titleBackground.subtitle = [_details valueForKey:@"genre"];
}


- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self hideToolbar];
}

#pragma mark -
#pragma mark Toolbar

- (TTView*) createToolbar
{
	_playButton = nil;
	_imdbButton = nil;
	_trailerButton = nil;
	_enqueueButton = nil;
	_toolbarButtons = [[NSMutableArray alloc] init];
	
    TTView* toolbar = [[[TTView alloc] initWithFrame:CGRectMake(0, -41, self.view.width, 41)] autorelease];
    toolbar.backgroundColor = [UIColor clearColor];
    toolbar.style = TTSTYLEVAR(tableToolbar);
	
	if ([_details objectForKey:@"imdb"])
	{
		_imdbButton = [TTButton buttonWithStyle:@"embossedButton:" title:@"Imdb"];
		_imdbButton.frame = CGRectMake(0, 0, 60, 30);
		[_imdbButton addTarget:self action:@selector(imdb:) forControlEvents:UIControlEventTouchUpInside];
		[toolbar addSubview:_imdbButton];
	}
    
    _playButton = [TTButton buttonWithStyle:@"embossedButton:" title:@"Play"];
    _playButton.frame = CGRectMake(0, 0, 50, 30);
    [_playButton addTarget:self action:@selector(play:) forControlEvents:UIControlEventTouchUpInside];
    [toolbar addSubview:_playButton];
    
    _enqueueButton = [TTButton buttonWithStyle:@"embossedButton:" title:@"Enqueue"];
    _enqueueButton.frame = CGRectMake(0, 0, 80, 30);
    [_enqueueButton addTarget:self action:@selector(enqueue:) forControlEvents:UIControlEventTouchUpInside];
    [toolbar addSubview:_enqueueButton];
    
	if ([_details objectForKey:@"trailerURL"])
	{
		_trailerButton = [TTButton buttonWithStyle:@"embossedButton:" title:@"Trailer"];
		_trailerButton.frame = CGRectMake(0, 0, 70, 30);
		[_trailerButton addTarget:self action:@selector(showTrailer:) forControlEvents:UIControlEventTouchUpInside];
		[toolbar addSubview:_trailerButton];
	}
	
    return toolbar;
}

- (void) hideToolbar
{
    [UIView beginAnimations:nil context:_toolBar];
    [UIView setAnimationDuration:TTSTYLEVAR(toolbarAnimationDuration)];
    _toolBar.bottom =  0;
    [UIView setAnimationDelegate:self];
    [UIView commitAnimations];
}

- (void) toggleToolbar
{
	
    if (_toolBar.bottom == 0)
	{
		[_toolbarButtons removeAllObjects];
        
        if ([XBMCStateListener connected])
        {
            _playButton.hidden = FALSE;
            _enqueueButton.hidden = FALSE;
            [_toolbarButtons addObject:_playButton];
            [_toolbarButtons addObject:_enqueueButton];
        }
        else
        {
            _playButton.hidden = TRUE;
            _enqueueButton.hidden = TRUE;
        }
        
        if (_trailerButton != nil)
        {
            _trailerButton.hidden = FALSE;
            [_toolbarButtons addObject:_trailerButton];
        }
        else
        {
            _trailerButton.hidden = TRUE;
        }
        
        if (_imdbButton != nil)
        {
            _imdbButton.hidden = FALSE;
            [_toolbarButtons addObject:_imdbButton];
        }
        else
        {
            _imdbButton.hidden = TRUE;
        }
		
		int nbButtons = [_toolbarButtons count];
		int buttonWidth = (_toolBar.width)/(nbButtons);
		int i = 0;
		for(TTButton *button in _toolbarButtons)
		{
			button.frame = CGRectMake(buttonWidth * i + buttonWidth/2 - button.width/2
									  , 5
									  , button.width
									  , button.height);
			i += 1;
			
		}
	}
    [UIView beginAnimations:nil context:_toolBar];
    [UIView setAnimationDuration:TTSTYLEVAR(toolbarAnimationDuration)];
    if (_toolBar.top == 0)
        _toolBar.bottom = 0;
    else _toolBar.top = 0;
    [UIView setAnimationDelegate:self];
    [UIView commitAnimations];
}

#pragma mark -
#pragma mark Poster + Fanart

- (void)coverLoaded:(NSDictionary*) result
{
    if ([result objectForKey:@"image"])
    {
        [_detailView.cover animateNewImage:[result objectForKey:@"image"]];
    }
}

- (void)fanartLoaded:(NSDictionary*) result
{
    if ([result objectForKey:@"image"])
    {
        [_detailView.fanart animateNewImage:[result objectForKey:@"image"]];
    }
}

-(void)tapCover:(UITapGestureRecognizer *)gesture
{
    [((AppDelegate*)[UIApplication sharedApplication].delegate) 
	 showFullscreenImage:[_details valueForKey:@"coverURL"]];
}

#pragma mark -
#pragma mark Notifications

- (void)disconnectedFromXBMC: (NSNotification *) notification
{
	//if we disconnect make sure the toolbar gets hidden so that we dont
	// have unwanted buttons
    [self hideToolbar];
}

#pragma mark -
#pragma mark Gestures

- (void)handleSwipe:(UISwipeGestureRecognizer *)recognizer 
{
    if (recognizer.state != UIGestureRecognizerStateRecognized) return;
    
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark -
#pragma mark Buttons

-(void) showTrailer:(id)sender
{
	[((AppDelegate*)[UIApplication sharedApplication].delegate) 
		showTrailer:[_details valueForKey:@"trailerURL"] 
			name:[_details valueForKey:@"label"]];
}
-(void) play:(id)sender
{
	[XBMCCommand play:[_details valueForKey:@"fileURL"]];
}
-(void) enqueue:(id)sender
{
	[XBMCCommand enqueue:[NSDictionary dictionaryWithObjectsAndKeys:@"movie", @"type"
						  , [_details valueForKey:@"id"], @"id", nil]];
}

-(void) imdb:(id)sender
{
    [((AppDelegate*)[UIApplication sharedApplication].delegate) showImdb:[_details valueForKey:@"imdb"]];
}
@end
