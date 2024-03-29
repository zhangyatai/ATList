//
//  ATList.m
//  ATList
//  https://github.com/ablettchen/ATList.git
//
//  Created by ablett on 2019/4/22.
//  Copyright (c) 2019 ablett. All rights reserved.
//

#import "ATList.h"
#import <MJRefresh/MJRefresh.h>
#import "ATRefreshHeader.h"
#import "ATRefreshGifHeader.h"
#import "ATRefreshFooter.h"

#if __has_include(<ATBlank/UIScrollView+ATBlank.h>)
#import <ATBlank/UIScrollView+ATBlank.h>
#else
#import "UIScrollView+ATBlank.h"
#endif

#if __has_include(<ATBlank/UIView+ATBlank.h>)
#import <ATBlank/UIView+ATBlank.h>
#else
#import "UIView+ATBlank.h"
#endif

#if __has_include(<ATCategories/ATCategories.h>)
#import <ATCategories/ATCategories.h>
#else
#import "ATCategories.h"
#endif

#if __has_include(<Reachability/Reachability.h>)
#import <Reachability/Reachability.h>
#else
#import "Reachability.h"
#endif

@interface ATListConf ()<NSCopying>
@end
@implementation ATListConf

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    [self reset];
    return self;
}

- (void)reset {
    self.customBlankView = nil;
    self.loadStyle = ATLoadStyleHeader;
    self.loadStrategy = ATLoadStrategyAuto;
    self.length = 0;
    self.blankDic = nil;
    self.loadHeaderStyle = ATLoadHeaderStyleNormal;
    
    NSMutableArray *gifImages = [NSMutableArray array];
    for (int i = 0; i < 23; i++) {
        UIImage *image = [UIImage imageNamed:[NSString stringWithFormat:@"refreshGif_%d", i+1] inBundle:[ATList listBundle]];
        if (image) {[gifImages addObject:image];}
    }
    // 设置默认Gif图片
    self.refreshingImages = gifImages;
}

- (id)copyWithZone:(NSZone __unused *)zone {
    ATListConf *conf = [ATListConf new];
    conf.customBlankView = self.customBlankView;
    conf.loadStyle = self.loadStyle;
    conf.loadStrategy = self.loadStrategy;
    conf.length = self.length;
    conf.blankDic = self.blankDic;
    conf.loadHeaderStyle = self.loadHeaderStyle;
    conf.refreshingImages = self.refreshingImages;
    return conf;
}

@end

@interface ATList ()

@property (assign, readwrite, nonatomic) enum ATLoadStatus loadStatus;      ///< 加载状态
@property (assign, readwrite, nonatomic) NSRange range;                     ///< 数据范围

@property (strong, nonatomic) NSValue *loadStatusValue;                     ///< 加载状态
@property (strong, nonatomic) NSValue *rangeValue;                          ///< 数据范围

@property (weak, nonatomic) __kindof UIScrollView *listView;                ///< 目标View
@property (strong, nonatomic) ATRefreshHeader *header;                      ///< 刷新头
@property (strong, nonatomic) ATRefreshGifHeader *gifHeader;                ///< 刷新头
@property (strong, nonatomic) ATRefreshFooter *footer;                      ///< 刷新尾
@property (assign, nonatomic) enum ATBlankType blankType;                   ///< 空白页类型
@property (strong, nonatomic) ATBlank *blank;                               ///< 空白页
@property (assign, nonatomic) NSInteger lastItemCount;                      ///< 记录上次条数

@end
@implementation ATList

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    
    self.loadStatus = ATLoadStatusIdle;
    self.range = NSMakeRange(0, self.conf.length);
    self.lastItemCount = 0;

    return self;
}

#pragma mark - setter, getter

- (ATRefreshHeader *)header {
    if (!_header) {
        _header = [ATRefreshHeader headerWithRefreshingTarget:self refreshingAction:@selector(pull_loadNewData)];
        [_header setTitle:@"下拉刷新" forState:MJRefreshStateIdle];
        [_header setTitle:@"释放更新" forState:MJRefreshStatePulling];
        [_header setTitle:@"加载中..." forState:MJRefreshStateRefreshing];
        _header.stateLabel.font = [UIFont systemFontOfSize:13];
        _header.lastUpdatedTimeLabel.font = [UIFont systemFontOfSize:14];
        _header.stateLabel.textColor = [UIColor colorWithWhite:0.584 alpha:1.000];
        _header.lastUpdatedTimeLabel.textColor = [UIColor colorWithWhite:0.584 alpha:1.000];
        _header.automaticallyChangeAlpha = YES;
        _header.lastUpdatedTimeLabel.hidden = YES;
    }
    return _header;
}

- (ATRefreshGifHeader *)gifHeader {
    if (!_gifHeader) {
        _gifHeader = [ATRefreshGifHeader headerWithRefreshingTarget:self refreshingAction:@selector(pull_loadNewData)];
        _gifHeader.stateLabel.hidden = YES;
        _gifHeader.automaticallyChangeAlpha = YES;
        _gifHeader.lastUpdatedTimeLabel.hidden = YES;
        _gifHeader.refreshingImages = self.conf.refreshingImages;
    }
    return _gifHeader;
}

- (ATRefreshFooter *)footer {
    if (!_footer) {
        _footer = [ATRefreshFooter footerWithRefreshingTarget:self refreshingAction:@selector(loadMoreData)];
        [_footer setTitle:@"上拉加载更多" forState:MJRefreshStateIdle];
        [_footer setTitle:@"加载中..." forState:MJRefreshStateRefreshing];
        [_footer setTitle:@"没有更多数据" forState:MJRefreshStateNoMoreData];
        _footer.stateLabel.font = [UIFont systemFontOfSize:13];
        _footer.stateLabel.textColor = [UIColor colorWithWhite:0.584 alpha:1.000];
    }
    return _footer;
}

- (void)setLoadStatusValue:(NSValue *)loadStatusValue {
    _loadStatusValue = loadStatusValue;
    enum ATLoadStatus loadStatus;
    [loadStatusValue getValue:&loadStatus];
    self.loadStatus = loadStatus;
}

- (void)setRangeValue:(NSValue *)rangeValue {
    _rangeValue = rangeValue;
    NSRange range;
    [rangeValue getValue:&range];
    self.range = range;
}

- (void)setConf:(ATListConf *)conf {
    if (conf == nil) {conf = [ATListConf new];}
    _conf = conf;
    if (!(conf.loadStyle | ATLoadStyleNone) ||
        ((conf.loadStyle & ATLoadStyleFooter) && !(conf.loadStyle & ATLoadStyleHeader))) {
        self.listView.mj_header = nil;
    }else if (((conf.loadStyle & ATLoadStyleHeader) && !(conf.loadStyle & ATLoadStyleFooter)) ||
              ((conf.loadStyle & ATLoadStyleHeader) && (conf.loadStyle & ATLoadStyleFooter))) {
        if (self.conf.loadHeaderStyle == ATLoadHeaderStyleNormal) {
            self.listView.mj_header = self.header;
        }else if (self.conf.loadHeaderStyle == ATLoadHeaderStyleGif) {
            self.listView.mj_header = self.gifHeader;
        }
    }
}

#pragma mark - privite

+ (NSBundle *)listBundle {
    NSString *bundlePath = [[NSBundle bundleForClass:self.class].resourcePath stringByAppendingPathComponent:@"ATList.bundle"];
    return [NSBundle bundleWithPath:bundlePath];
}

- (void)loadMoreData {
    if (self.loadStatus != ATLoadStatusIdle) {return;}
    
    self.loadStatus = ATLoadStatusMore;
    int loc = ceil((float)self.listView.itemsCount / self.conf.length) ? : 1;
    self.range = NSMakeRange(loc*self.conf.length, self.conf.length);
    
    SEL loadMoreSEL = NSSelectorFromString(@"loadMoreData");
    AT_SAFE_PERFORM_SELECTOR(self.listView, loadMoreSEL, nil);
}

- (void)reloadData {
    SEL reloadSEL = NSSelectorFromString(@"reloadData");
    if (!AT_SAFE_PERFORM_SELECTOR(self.listView, reloadSEL, nil)) {
        [self.listView setNeedsDisplay];
    }
}

- (void)setBlankType:(enum ATBlankType)blankType {
    _blankType = blankType;
    if (!self.conf.blankDic || self.conf.blankDic.count == 0) {
        self.blank = [ATBlank defaultBlankWithType:blankType];
    }else {
        Reachability *rech = [Reachability reachabilityForInternetConnection];
        if (self.conf.blankDic[@(blankType)]) {
            // 无网络时优先显示无网络页面
            if (rech.currentReachabilityStatus == NotReachable) {
                self.blank = self.conf.blankDic[@(ATBlankTypeNoNetwork)];
            }else {
                self.blank = self.conf.blankDic[@(blankType)];
            }
        }else {
            // 无网络时优先显示无网络页面
            if (rech.currentReachabilityStatus == NotReachable) {
                self.blank = [ATBlank defaultBlankWithType:ATBlankTypeNoNetwork];
            }else {
                self.blank = [ATBlank defaultBlankWithType:blankType];
            }
        }
    }
    
    @weakify(self);
    self.blank.tapBlock = ^{
        @strongify(self);
        if (!self.blank.isAnimating) {
            self.blank.isAnimating = YES;
            [self.listView reloadBlank];
            [self loadNewData];
        }
    };
    
    self.blank.customBlankView = self.conf.customBlankView;
    [self.listView setBlank:self.blank];
    [self.listView reloadBlank];
}

#pragma mark - public

- (void)finish:(nullable NSError *)error {
    if (self.blank.isAnimating) {self.blank.isAnimating = NO;}
    [self.listView reloadBlank];
    
    // 解决非控件触发的刷新（使用者直接调用 finish:）而导致 loadStatus 无法得到正确的状态，致使无法正确显示页面，故此处需要重设 loadStatus = ATLoadStatusNew
    if (self.loadStatus == ATLoadStatusIdle) {self.loadStatus = ATLoadStatusNew;}
    
    if (self.loadStatus == ATLoadStatusNew) {
        [self.listView.mj_header endRefreshing];
        [self.listView.mj_footer resetNoMoreData];
        if (self.listView.itemsCount == 0) {
            if (error) {
                self.blankType = ATBlankTypeFailure;
            }else {
                self.blankType = ATBlankTypeNoData;
            }
        }else {
            if (((self.conf.loadStyle & ATLoadStyleFooter) && !(self.conf.loadStyle & ATLoadStyleHeader)) ||
                ((self.conf.loadStyle & ATLoadStyleHeader) && (self.conf.loadStyle & ATLoadStyleFooter))) {
                if (self.listView.itemsCount >= self.conf.length) {
                    self.listView.mj_footer = self.footer;
                }else {
                    self.listView.mj_footer = nil;
                }
            }
        }
    }else if (self.loadStatus == ATLoadStatusMore) {
        if ((self.listView.itemsCount - self.lastItemCount) < self.range.length) {
            [self.listView.mj_footer endRefreshingWithNoMoreData];
        }else {
            self.listView.mj_footer = self.footer;
            [self.listView.mj_footer endRefreshing];
        }
    }
    
    [self reloadData];
    self.loadStatus = ATLoadStatusIdle;
    
    self.lastItemCount = self.listView.itemsCount;
}

- (void)pull_loadNewData {
    if (self.loadStatus != ATLoadStatusIdle) {return;}
    
    self.loadStatus = ATLoadStatusNew;
    self.range = NSMakeRange(0, self.conf.length);
    self.lastItemCount = 0;
    
    SEL loadNewSEL = NSSelectorFromString(@"loadNewData");
    AT_SAFE_PERFORM_SELECTOR(self.listView, loadNewSEL, nil);
}

- (void)loadNewData {
    if (self.conf.loadStrategy == ATLoadStrategyManual &&
        (((self.conf.loadStyle & ATLoadStyleHeader) && !(self.conf.loadStyle & ATLoadStyleFooter)) ||
         ((self.conf.loadStyle & ATLoadStyleHeader) && (self.conf.loadStyle & ATLoadStyleFooter)))) {
        [self beginning];
    }else {
        [self pull_loadNewData];
    }
}

- (void)beginning {
    if (self.conf.loadHeaderStyle == ATLoadHeaderStyleNormal) {
        [self.header beginRefreshing];
    }else if (self.conf.loadHeaderStyle == ATLoadHeaderStyleGif) {
        [self.gifHeader beginRefreshing];
    }
}

@end


@implementation ATListDefaultConf

+ (instancetype)defaultConf {
    static id sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[[self class] alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    return self;
}

- (void)setupConf:(void(^)(ATListConf * _Nonnull conf))block {
    ATListConf *conf = [ATListConf new];
    AT_SAFE_BLOCK(block, conf);
    self.conf = conf;
}

+ (void)setupConf:(void(^)(ATListConf * _Nonnull conf))block {
    [[ATListDefaultConf defaultConf] setupConf:block];
}

@end
