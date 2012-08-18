/*
 * Created by Mayur Pawashe on 5/11/11.
 *
 * Copyright (c) 2012 zgcoder
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * Redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 *
 * Neither the name of the project's author nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 * TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "ZGMemoryViewer.h"
#import "ZGStatusBarRepresenter.h"
#import "ZGLineCountingRepresenter.h"
#import "ZGVerticalScrollerRepresenter.h"
#import "ZGProcess.h"
#import "ZGAppController.h"
#import "ZGUtilities.h"
#import "ZGCalculator.h"
#import "ZGVirtualMemory.h"

#define READ_MEMORY_INTERVAL 0.1
#define DEFAULT_MINIMUM_LINE_DIGIT_COUNT 12

#define ZGMemoryViewerAddressField @"ZGMemoryViewerAddressField"
#define ZGMemoryViewerSizeField @"ZGMemoryViewerSizeField"
#define ZGMemoryViewerAddress @"ZGMemoryViewerAddress"
#define ZGMemoryViewerSize @"ZGMemoryViewerSize"
#define ZGMemoryViewerProcessName @"ZGMemoryViewerProcessName"

@interface ZGMemoryViewer ()

@property (readwrite, strong) NSTimer *checkMemoryTimer;

@property (readwrite, strong) ZGStatusBarRepresenter *statusBarRepresenter;
@property (readwrite, strong) ZGLineCountingRepresenter *lineCountingRepresenter;

@property (readwrite) ZGMemoryAddress currentMemoryAddress;
@property (readwrite) ZGMemorySize currentMemorySize;

@property (assign) IBOutlet NSPopUpButton *runningApplicationsPopUpButton;
@property (assign) IBOutlet NSTextField *addressTextField;
@property (assign) IBOutlet HFTextView *textView;

@end

@implementation ZGMemoryViewer

#pragma mark Accessors

- (ZGMemoryAddress)selectedAddress
{
	return (self.currentMemorySize > 0) ? ((ZGMemoryAddress)([[self.textView.controller.selectedContentsRanges objectAtIndex:0] HFRange].location) + self.currentMemoryAddress) : 0x0;
}

#pragma mark Setters

- (void)setCurrentProcess:(ZGProcess *)newProcess
{
	_currentProcess = newProcess;
	if (_currentProcess && ![_currentProcess hasGrantedAccess])
	{
		if (![_currentProcess grantUsAccess])
		{
			NSLog(@"Memory viewer failed to grant access to PID %d", _currentProcess.processID);
		}
	}
	
	[self changeMemoryView:nil];
}

#pragma mark Initialization

- (id)init
{
	self = [super initWithWindowNibName:@"MemoryViewer"];
	
	[self setWindowFrameAutosaveName:@"ZGMemoryViewer"];
	
	return self;
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
    [super encodeRestorableStateWithCoder:coder];
    
    [coder
		 encodeObject:self.addressTextField.stringValue
		 forKey:ZGMemoryViewerAddressField];
    
    [coder
		 encodeInt64:(int64_t)self.currentMemoryAddress
		 forKey:ZGMemoryViewerAddress];
    
    [coder
		 encodeObject:[self.runningApplicationsPopUpButton.selectedItem.representedObject name]
		 forKey:ZGMemoryViewerProcessName];
}

- (void)restoreStateWithCoder:(NSCoder *)coder
{
	[super restoreStateWithCoder:coder];
	
	NSString *memoryViewerAddressField = [coder decodeObjectForKey:ZGMemoryViewerAddressField];
	if (memoryViewerAddressField)
	{
		self.addressTextField.stringValue = memoryViewerAddressField;
	}
	
	self.currentMemoryAddress = [coder decodeInt64ForKey:ZGMemoryViewerAddress];
	
	[self updateRunningApplicationProcesses:[coder decodeObjectForKey:ZGMemoryViewerProcessName]];
}

- (void)markChanges
{
	if ([self respondsToSelector:@selector(invalidateRestorableState)])
	{
		[self invalidateRestorableState];
	}
}

- (void)windowDidLoad
{
	// For handling windowWillClose:
	self.window.delegate = self;
	
	self.window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
	
	if ([self.window respondsToSelector:@selector(setRestorable:)] && [self.window respondsToSelector:@selector(setRestorationClass:)])
	{
		self.window.restorable = YES;
		self.window.restorationClass = ZGAppController.class;
		self.window.identifier = ZGMemoryViewerIdentifier;
		[self markChanges];
	}

	[self updateRunningApplicationProcesses:[[ZGAppController sharedController] lastSelectedProcessName]];
	
	[[NSWorkspace sharedWorkspace]
	 addObserver:self
	 forKeyPath:@"runningApplications"
	 options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
	 context:NULL];
	
	self.textView.controller.editable = NO;
	
	// So, I've no idea what HFTextView does by default, remove any type of representer that it might have and that we want to add
	NSMutableArray *representersToRemove = [[NSMutableArray alloc] init];
	
	for (HFRepresenter *representer in self.textView.layoutRepresenter.representers)
	{
		if ([representer isKindOfClass:HFStatusBarRepresenter.class] || [representer isKindOfClass:HFLineCountingRepresenter.class] || [representer isKindOfClass:HFVerticalScrollerRepresenter.class])
		{
			[representersToRemove addObject:representer];
		}
	}
	
	for (HFRepresenter *representer in representersToRemove)
	{
		[self.textView.layoutRepresenter removeRepresenter:representer];
	}
	
	// Add custom status bar
	self.statusBarRepresenter = [[ZGStatusBarRepresenter alloc] init];
	self.statusBarRepresenter.statusMode = HFStatusModeHexadecimal;
	
	[self.textView.controller addRepresenter:self.statusBarRepresenter];
	[[self.textView layoutRepresenter] addRepresenter:self.statusBarRepresenter];
	
	// Add custom line counter
	self.lineCountingRepresenter = [[ZGLineCountingRepresenter alloc] init];
	self.lineCountingRepresenter.minimumDigitCount = DEFAULT_MINIMUM_LINE_DIGIT_COUNT;
	self.lineCountingRepresenter.lineNumberFormat = HFLineNumberFormatHexadecimal;
	
	[self.textView.controller addRepresenter:self.lineCountingRepresenter];
	[self.textView.layoutRepresenter addRepresenter:self.lineCountingRepresenter];
	
	// Add custom scroller
	ZGVerticalScrollerRepresenter *verticalScrollerRepresenter = [[ZGVerticalScrollerRepresenter alloc] init];
	
	[self.textView.controller addRepresenter:verticalScrollerRepresenter];
	[self.textView.layoutRepresenter addRepresenter:verticalScrollerRepresenter];
}

- (IBAction)showWindow:(id)sender
{
	[super showWindow:sender];
	
	if (!self.checkMemoryTimer)
	{
		self.checkMemoryTimer =
			[NSTimer
			 scheduledTimerWithTimeInterval:READ_MEMORY_INTERVAL
			 target:self
			 selector:@selector(readMemory:)
			 userInfo:nil
			 repeats:YES];
	}
}

- (void)windowWillClose:(NSNotification *)notification
{
	[self.checkMemoryTimer invalidate];
	self.checkMemoryTimer = nil;
}

#pragma mark Updating running applications

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == NSWorkspace.sharedWorkspace)
	{
		[self updateRunningApplicationProcesses:nil];
	}
}

- (void)clearData
{
	self.currentMemoryAddress = 0;
	self.currentMemorySize = 0;
	self.lineCountingRepresenter.beginningMemoryAddress = 0;
	self.statusBarRepresenter.beginningMemoryAddress = 0;
	self.textView.data = [NSData data];
}

- (void)updateRunningApplicationProcesses:(NSString *)desiredProcessName
{
	[self.runningApplicationsPopUpButton removeAllItems];
	
	NSMenuItem *firstRegularApplicationMenuItem = nil;
	
	BOOL foundTargettedProcess = NO;
	NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"activationPolicy" ascending:YES];
	for (NSRunningApplication *runningApplication in  [NSWorkspace.sharedWorkspace.runningApplications sortedArrayUsingDescriptors:@[sortDescriptor]])
	{
		if (runningApplication.processIdentifier != NSRunningApplication.currentApplication.processIdentifier)
		{
			NSMenuItem *menuItem = [[NSMenuItem alloc] init];
			menuItem.title = [NSString stringWithFormat:@"%@ (%d)", runningApplication.localizedName, runningApplication.processIdentifier];
			NSImage *iconImage = runningApplication.icon;
			iconImage.size = NSMakeSize(16, 16);
			menuItem.image = iconImage;
			ZGProcess *representedProcess =
				[[ZGProcess alloc]
				 initWithName:runningApplication.localizedName
				 processID:runningApplication.processIdentifier
				 set64Bit:(runningApplication.executableArchitecture == NSBundleExecutableArchitectureX86_64)];
			
			menuItem.representedObject = representedProcess;
			
			[self.runningApplicationsPopUpButton.menu addItem:menuItem];
			
			if (!firstRegularApplicationMenuItem && runningApplication.activationPolicy == NSApplicationActivationPolicyRegular)
			{
				firstRegularApplicationMenuItem = menuItem;
			}
			
			if (self.currentProcess.processID == runningApplication.processIdentifier || [desiredProcessName isEqualToString:runningApplication.localizedName])
			{
				[self.runningApplicationsPopUpButton selectItem:self.runningApplicationsPopUpButton.lastItem];
				foundTargettedProcess = YES;
			}
		}
	}
	
	if (!foundTargettedProcess)
	{
		if (firstRegularApplicationMenuItem)
		{
			[self.runningApplicationsPopUpButton selectItem:firstRegularApplicationMenuItem];
		}
		else if ([self.runningApplicationsPopUpButton indexOfSelectedItem] >= 0)
		{
			[self.runningApplicationsPopUpButton selectItemAtIndex:0];
		}
	}
	
	self.currentProcess = self.runningApplicationsPopUpButton.selectedItem.representedObject;
}

- (IBAction)runningApplicationsPopUpButton:(id)sender
{
	if ([self.runningApplicationsPopUpButton.selectedItem.representedObject processID] != self.currentProcess.processID)
	{
		self.currentProcess = self.runningApplicationsPopUpButton.selectedItem.representedObject;
	}
}

#pragma mark Reading from Memory

- (IBAction)changeMemoryView:(id)sender
{
	BOOL success = NO;
	
	if ([self.currentProcess hasGrantedAccess])
	{
		NSString *calculatedMemoryAddressExpression = [ZGCalculator evaluateExpression:self.addressTextField.stringValue];
		
		ZGMemoryAddress calculatedMemoryAddress = 0;
		
		if (isValidNumber(calculatedMemoryAddressExpression))
		{
			calculatedMemoryAddress = memoryAddressFromExpression(calculatedMemoryAddressExpression);
		}
		
		NSArray *memoryRegions = ZGRegionsForProcessTask(self.currentProcess.processTask);
		if (memoryRegions.count == 0)
		{
			success = NO;
		}
		else
		{
			ZGRegion *chosenRegion = nil;
			if (calculatedMemoryAddress != 0)
			{
				for (ZGRegion *region in memoryRegions)
				{
					if (calculatedMemoryAddress >= region.address && calculatedMemoryAddress < region.address + region.size)
					{
						chosenRegion = region;
						break;
					}
				}
			}
			
			if (!chosenRegion || !(chosenRegion.protection & VM_PROT_READ))
			{
				chosenRegion = nil;
				for (ZGRegion *region in memoryRegions)
				{
					if (region.protection & VM_PROT_READ)
					{
						chosenRegion = region;
						break;
					}
				}
				if (!chosenRegion)
				{
					chosenRegion = [memoryRegions objectAtIndex:0];
				}
				
				calculatedMemoryAddress = 0;
			}
			
			self.currentMemoryAddress = chosenRegion.address;
			self.currentMemorySize = chosenRegion.size;
			
			ZGMemoryAddress memoryAddress = self.currentMemoryAddress;
			ZGMemorySize memorySize = self.currentMemorySize;
			
			void *bytes = NULL;
			
			if (ZGReadBytes(self.currentProcess.processTask, memoryAddress, &bytes, &memorySize) && memorySize > 0)
			{
				// Replace all the contents of the self.textView
				self.textView.data = [NSData dataWithBytes:bytes length:(NSUInteger)memorySize];
				self.currentMemoryAddress = memoryAddress;
				self.currentMemorySize = memorySize;
				
				self.statusBarRepresenter.beginningMemoryAddress = self.currentMemoryAddress;
				// Select the first byte of data
				self.statusBarRepresenter.controller.selectedContentsRanges = @[[HFRangeWrapper withRange:HFRangeMake(0, 0)]];
				// To make sure status bar doesn't always show 0x0 as the offset, we need to force it to update
				[self.statusBarRepresenter updateString];
				
				self.lineCountingRepresenter.minimumDigitCount = HFCountDigitsBase16(memoryAddress + memorySize);
				self.lineCountingRepresenter.beginningMemoryAddress = self.currentMemoryAddress;
				// This will force the line numbers to update
				[self.lineCountingRepresenter.view setNeedsDisplay:YES];
				// This will force the line representer's layout to re-draw, which is necessary from calling setMinimumDigitCount:
				[self.textView.layoutRepresenter performLayout];
				
				success = YES;
				
				ZGFreeBytes(self.currentProcess.processTask, bytes, memorySize);
				
				if (!calculatedMemoryAddress)
				{
					self.addressTextField.stringValue = [NSString stringWithFormat:@"0x%llX", memoryAddress];
					calculatedMemoryAddress = memoryAddress;
				}
				
				[self.window makeFirstResponder:self.textView];
				
				[self jumpToMemoryAddress:calculatedMemoryAddress];
			}
		}
	}
	
	[self markChanges];
	
	if (!success)
	{
		[self clearData];
	}
}

- (void)readMemory:(NSTimer *)timer
{
	if (self.currentMemorySize > 0)
	{
		HFFPRange displayedLineRange = self.textView.controller.displayedLineRange;
		
		ZGMemoryAddress displayedLocation = (ZGMemoryAddress)(displayedLineRange.location * self.textView.controller.bytesPerLine);
		ZGMemoryAddress displayedEndLocation = (ZGMemoryAddress)(self.textView.controller.bytesPerLine * (displayedLineRange.location + displayedLineRange.length));
		
		ZGMemoryAddress minimumLocation = self.textView.controller.minimumSelectionLocation;
		ZGMemoryAddress maximumLocation = self.textView.controller.maximumSelectionLocation;
		
		// If the current selection is not visible, then make it visible
		// If we replace the bytes and the current selection is not visible, it will scroll to the current selection
		// So we need to change the current selection accordingly
		if ((minimumLocation < displayedLocation || minimumLocation >= displayedEndLocation) || (maximumLocation < displayedLocation || maximumLocation >= displayedEndLocation))
		{
			self.textView.controller.selectedContentsRanges = @[[HFRangeWrapper withRange:HFRangeMake(ceill(displayedLineRange.location) * self.textView.controller.bytesPerLine, 0)]];
			displayedLineRange = self.textView.controller.displayedLineRange;
		}
		
		ZGMemoryAddress readAddress = (ZGMemoryAddress)(displayedLineRange.location * self.textView.controller.bytesPerLine) + self.currentMemoryAddress;
		
		if (readAddress >= self.currentMemoryAddress && readAddress < self.currentMemoryAddress + self.currentMemorySize)
		{
			// Try to read two extra lines, to make sure we at least get the upper and lower fractional parts.
			ZGMemorySize readSize = (ZGMemorySize)((displayedLineRange.length + 2) * self.textView.controller.bytesPerLine);
			// If we go over in size, resize it to the end
			if (readAddress + readSize > self.currentMemoryAddress + self.currentMemorySize)
			{
				readSize = (self.currentMemoryAddress + self.currentMemorySize) - readAddress;
			}
			
			void *bytes = NULL;
			if (ZGReadBytes(self.currentProcess.processTask, readAddress, &bytes, &readSize) && readSize > 0)
			{
				HFFullMemoryByteSlice *byteSlice = [[HFFullMemoryByteSlice alloc] initWithData:[NSData dataWithBytes:bytes length:(NSUInteger)readSize]];
				HFByteArray *newByteArray = self.textView.controller.byteArray;
				
				[newByteArray insertByteSlice:byteSlice inRange:HFRangeMake((ZGMemoryAddress)(displayedLineRange.location * self.textView.controller.bytesPerLine), readSize)];
				[self.textView.controller replaceByteArray:newByteArray];
				
				ZGFreeBytes(self.currentProcess.processTask, bytes, readSize);
			}
		}
	}
}

// memoryAddress is assumed to be within bounds of current memory region being viewed
- (void)jumpToMemoryAddress:(ZGMemoryAddress)memoryAddress
{
	ZGMemoryAddress offset = (ZGMemoryAddress)(memoryAddress - self.currentMemoryAddress);
	
	long double offsetLine = ((long double)offset) / [self.textView.controller bytesPerLine];
	
	HFFPRange displayedLineRange = self.textView.controller.displayedLineRange;
	
	if (offsetLine < displayedLineRange.location || offsetLine > displayedLineRange.location + displayedLineRange.length)
	{
		[self.textView.controller scrollByLines:offsetLine - displayedLineRange.location];
	}
	
	// Select one byte from the offset
	self.textView.controller.selectedContentsRanges = @[[HFRangeWrapper withRange:HFRangeMake(offset, 1)]];
	[self.textView.controller pulseSelection];
}

@end
