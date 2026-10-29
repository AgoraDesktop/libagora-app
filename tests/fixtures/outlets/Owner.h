/* The fixture: what a class's DECLARATIONS say, which is what a "Connect" list must show. `_delegate` is
 * storage and must not appear; `_runButton` and `titleField` are outlets and must. */
#import <Foundation/NSObject.h>

@interface Owner : NSObject
{
	IBOutlet id _runButton;
	IBOutlet id titleField;
	id _delegate;
}
@property (assign) IBOutlet id windowOutlet;
- (IBAction)go:(id)sender;
- (void)notAnAction;
@end
