#import <AppKit/AppKit.h>

extern void DFRElementSetControlStripPresenceForIdentifier(NSTouchBarItemIdentifier _Nonnull, BOOL);
extern void DFRSystemModalShowsCloseBoxWhenFrontMost(BOOL);

@interface NSTouchBar (SystemModal)
+ (void)presentSystemModalTouchBar:(nullable NSTouchBar *)touchBar
          systemTrayItemIdentifier:(nonnull NSTouchBarItemIdentifier)identifier;
+ (void)presentSystemModalTouchBar:(nullable NSTouchBar *)touchBar
                         placement:(long long)placement
          systemTrayItemIdentifier:(nonnull NSTouchBarItemIdentifier)identifier;
+ (void)dismissSystemModalTouchBar:(nullable NSTouchBar *)touchBar;
@end

@interface NSTouchBarItem (SystemTray)
+ (void)addSystemTrayItem:(nonnull NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(nonnull NSTouchBarItem *)item;
@end
