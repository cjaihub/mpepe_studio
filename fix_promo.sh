#!/bin/bash
# First change ALL `shape: BoxShape.circle` back to `borderRadius: BorderRadius.circular(16)` where it was messed up. 
# Wait, let's just use perl or awk to replace it precisely in the PromoBanner method.
awk '/_buildPromoBanner/{flag=1} /shape: BoxShape.circle,/{if(flag){sub("shape: BoxShape.circle,","borderRadius: BorderRadius.circular(16),"); flag=0}} 1' lib/inbox/mobile/inbox_mobile_screen.dart > temp.dart && mv temp.dart lib/inbox/mobile/inbox_mobile_screen.dart
