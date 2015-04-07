
#import "BottomMenu.h"
#import "BottomMenuCell.h"
#import "UIKitCategories.h"
#include "../../../platform/platform.hpp"
#include "../../../platform/settings.hpp"
#import "AppInfo.h"
#import "ImageDownloader.h"
#import "MapsAppDelegate.h"
#import "Framework.h"

@interface BottomMenu () <UITableViewDataSource, UITableViewDelegate, ImageDownloaderDelegate>

@property (nonatomic) UITableView * tableView;
@property (nonatomic) SolidTouchView * fadeView;
@property (nonatomic) NSArray * items;
@property (nonatomic) NSMutableDictionary * imageDownloaders;

@end

@implementation BottomMenu

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];

  self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

  [self addSubview:self.fadeView];
  [self addSubview:self.tableView];

  _menuHidden = YES;

  self.imageDownloaders = [[NSMutableDictionary alloc] init];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appInfoSynced:) name:AppInfoSyncedNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(outOfDateCountriesCountChanged:) name:MapsStatusChangedNotification object:nil];

  return self;
}

- (void)outOfDateCountriesCountChanged:(NSNotification *)notification
{
  NSInteger const row = [self.items indexOfObjectPassingTest:^(id obj, NSUInteger i, BOOL *stop){
    return [obj[@"Id"] isEqualToString:@"Maps"];
  }];
  BottomMenuCell * cell = (BottomMenuCell *)[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
  cell.badgeView.value = [[notification userInfo][@"OutOfDate"] integerValue];
}

- (NSArray *)generateItems
{
  NSMutableArray * items = [[NSMutableArray alloc] init];
  bool adsEnabled = true;
  (void)Settings::Get("MenuLinksEnabled", adsEnabled);
  if (adsEnabled)
  {
    NSArray * serverItems = [[AppInfo sharedInfo] featureValue:AppFeatureBottomMenuItems forKey:@"Items"];
    if ([serverItems count])
      [items addObjectsFromArray:serverItems];
  }

  NSArray * standardItems = @[@{@"Id" : @"Maps", @"Title" : L(@"download_maps"), @"Icon" : @"IconMap"},
                              @{@"Id" : @"Settings", @"Title" : L(@"settings_and_more"), @"Icon" : @"IconSettings"},
                              @{@"Id" : @"Share", @"Title" : L(@"share_my_location"), @"Icon" : @"IconShare"}];
  [items addObjectsFromArray:standardItems];

  return items;
}

- (void)appInfoSynced:(NSNotification *)notification
{
  [self reload];
}

- (void)didMoveToSuperview
{
  [self reload];
}

- (void)reload
{
  self.items = [self generateItems];
  [self.tableView reloadData];
  [self align];
}

- (void)align
{
  CGFloat menuHeight = [self.items count] * [BottomMenuCell cellHeight];
  if (self.superview.width > self.superview.height)
    menuHeight = MIN(menuHeight, IPAD ? menuHeight : self.superview.height - 92);

  self.tableView.frame = CGRectMake(self.tableView.minX, self.tableView.minY, self.width, menuHeight);

  [self setMenuHidden:self.menuHidden animated:NO];
}

- (void)layoutSubviews
{
  [self align];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
  return [self.items count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
  NSDictionary * item = self.items[indexPath.row];

  BottomMenuCell * cell = (BottomMenuCell *)[tableView dequeueReusableCellWithIdentifier:[BottomMenuCell className]];
  if (!cell)
    cell = [[BottomMenuCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:[BottomMenuCell className]];

  if (item[@"Icon"])
  {
    cell.iconImageView.image = [UIImage imageNamed:item[@"Icon"]];
  }
  else if (item[@"IconURLs"])
  {
    NSString * itemId = item[@"Id"];
    NSString * imageName = itemId;
    NSString * imagePath = [[self imagesPath] stringByAppendingPathComponent:imageName];
    NSData * imageData = [NSData dataWithContentsOfFile:imagePath];
    UIImage * image;
    if (imageData)
      image = [UIImage imageWithData:imageData scale:[UIScreen mainScreen].scale];
    if (image)
      cell.iconImageView.image = image;
    else if (!self.imageDownloaders[itemId])
    {
      ImageDownloader * downloader = [[ImageDownloader alloc] init];
      downloader.delegate = self;
      downloader.objectId = itemId;
      self.imageDownloaders[itemId] = downloader;

      NSDictionary * links = item[@"IconURLs"];
      NSString * key = [NSString stringWithFormat:@"%ix", (NSInteger)[UIScreen mainScreen].scale];
      NSString * link = links[key];
      [downloader startDownloadingWithURL:[NSURL URLWithString:link]];
    }
  }

  cell.titleLabel.textColor = item[@"Color"] ? [UIColor colorWithColorCode:item[@"Color"]] : [UIColor whiteColor];

  if (item[@"Title"])
  {
    cell.titleLabel.text = item[@"Title"];
  }
  else if (item[@"Titles"])
  {
    NSDictionary * titles = item[@"Titles"];
    NSString * title = titles[[[NSLocale preferredLanguages] firstObject]];
    if (!title)
      title = titles[@"*"];

    cell.titleLabel.text = title;
  }

  if ([item[@"Id"] isEqualToString:@"Maps"])
    cell.badgeView.value = GetFramework().GetCountryTree().GetActiveMapLayout().GetOutOfDateCount();
  else
    cell.badgeView.value = 0;

  if (indexPath.row == [self.items count] - 1)
    cell.separator.hidden = YES;

  return cell;
}

- (void)imageDownloaderDidFinishLoading:(ImageDownloader *)downloader
{
  NSInteger row = 0;
  for (NSInteger i = 0; i < [self.items count]; i++)
  {
    if ([self.items[i][@"Id"] isEqualToString:downloader.objectId])
    {
      row = i;
      break;
    }
  }
  BottomMenuCell * cell = (BottomMenuCell *)[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
  cell.iconImageView.image = downloader.image;

  NSString * imageName = downloader.objectId;
  NSString * imagePath = [[self imagesPath] stringByAppendingPathComponent:imageName];
  [UIImagePNGRepresentation(downloader.image) writeToFile:imagePath atomically:YES];

  [self.imageDownloaders removeObjectForKey:downloader.objectId];
}

- (NSString *)imagesPath
{
  NSString * libraryPath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
  NSString * path = [libraryPath stringByAppendingPathComponent:@"bottom_menu_images/"];
  if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:nil])
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:nil];
  return path;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
  return [BottomMenuCell cellHeight];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
  NSDictionary * item = self.items[indexPath.row];
  NSDictionary * urls = item[@"WebURLs"];
  NSString * url = urls[[[NSLocale preferredLanguages] firstObject]];
  if (!url)
    url = urls[@"*"];
  [self.delegate bottomMenu:self didPressItemWithName:item[@"Id"] appURL:item[@"AppURL"] webURL:url];
  [self.tableView deselectRowAtIndexPath:self.tableView.indexPathForSelectedRow animated:YES];
}

- (void)setMenuHidden:(BOOL)hidden animated:(BOOL)animated
{
  _menuHidden = hidden;
  [UIView animateWithDuration:(animated ? 0.25 : 0) delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
    if (hidden)
    {
      self.userInteractionEnabled = NO;
      self.tableView.minY = self.tableView.superview.height;
      self.fadeView.alpha = 0;
    }
    else
    {
      self.userInteractionEnabled = YES;
      self.tableView.maxY = self.tableView.superview.height;
      self.fadeView.alpha = 1;
    }
  } completion:^(BOOL finished) {}];
}

- (void)tap:(UITapGestureRecognizer *)sender
{
  [self setMenuHidden:YES animated:YES];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
  return !self.menuHidden;
}

- (UITableView *)tableView
{
  if (!_tableView)
  {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.alwaysBounceVertical = NO;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.backgroundColor = [UIColor colorWithColorCode:@"1D1F29"];
  }
  return _tableView;
}

- (SolidTouchView *)fadeView
{
  if (!_fadeView)
  {
    _fadeView = [[SolidTouchView alloc] initWithFrame:self.bounds];
    _fadeView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    _fadeView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    UITapGestureRecognizer * tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
    [_fadeView addGestureRecognizer:tap];
  }
  return _fadeView;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end