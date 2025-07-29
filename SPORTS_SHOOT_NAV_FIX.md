# SportsShootListView Navigation Fix

## Issue
SportsShootListView had a NavigationView in its iPhone layout, causing double back buttons when navigating to SportsShootDetailView.

## Solution
Removed the NavigationView wrapper from the iPhone view since SportsShootListView is already presented within MainEmployeeView's navigation context.

## Changes Made
1. **iPhoneView**: Removed NavigationView wrapper, kept List and all content
2. **iPad view**: Left unchanged as it uses DoubleColumnNavigationViewStyle for split view layout

## Result
- Single back button when viewing sports shoot details on iPhone
- iPad split view navigation continues to work correctly
- Consistent navigation experience across the app