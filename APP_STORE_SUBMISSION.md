# StepOut - App Store Submission Guide

**Quick reference for submitting StepOut v1.0 to the App Store**

---

## ✅ What's Already Done

1. **Info.plist Privacy Descriptions** - All required permissions added ✓
2. **App Version** - 1.0, Build 1 ✓
3. **Bundle ID** - com.stepout2.app ✓
4. **App builds successfully** ✓

---

## 📝 Next Steps (Total: ~2 hours)

### Step 1: Host Privacy Policy (10 minutes)

**Easiest Option: GitHub Pages**
1. Create free GitHub account: https://github.com/signup
2. Create new **public** repository: `stepout-privacy`
3. Upload the privacy policy (I can create it for you)
4. Settings → Pages → Enable from `main` branch
5. URL: `https://[your-username].github.io/stepout-privacy/`

**Alternative: Google Docs**
1. Create new Google Doc
2. Paste privacy policy content
3. Share → "Anyone with link" → Copy link

**Save the URL** - you'll need it for App Store Connect!

---

### Step 2: Create Demo Account (5 minutes)

**Firebase Console Method:**
1. Go to: https://console.firebase.google.com
2. Select project: `stepout-3db1a`
3. Authentication → Users → Add User
4. Credentials:
   ```
   Email: demo@stepout.app
   Password: StepOut2025!
   ```
5. Click three dots (⋮) → Verify email

**Test it:** Sign into the app with these credentials!

---

### Step 3: Take Screenshots (20 minutes)

**Required Size:** 6.7" display (iPhone 16 Pro Max or 15 Plus)

**Quick Method:**
```bash
# Open simulator
open -a Simulator

# Select: Hardware → Device → iPhone 16 Pro Max
```

**In Xcode:**
- Select destination: iPhone 16 Pro Max
- Click Run (▶) or press Cmd+R

**Sign in:** demo@stepout.app / StepOut2025!

**Take 5 Screenshots** (Press **Cmd+S** in simulator):

1. **Events Feed** - Home screen with events
2. **Event Details** - Tap event, show full details
3. **Create Event** - Tap +, show form with categories
4. **Search/Filter** - Show category filters working
5. **Profile Calendar** - Profile tab with calendar

Screenshots save to Desktop at 1290 x 2796 pixels (perfect!)

---

### Step 4: Configure Xcode Signing (5 minutes)

1. Open Xcode
2. Click StepOut project (left sidebar)
3. Select "StepOut" target
4. Click "Signing & Capabilities" tab
5. **Set:**
   - Team: Your Apple Developer team
   - ✓ Automatically manage signing
   - Bundle Identifier: com.stepout2.app

✅ No errors? Ready to archive!

---

### Step 5: Archive for App Store (30 minutes)

**In Xcode:**

1. Change destination to: **"Any iOS Device (arm64)"**
2. Product → **Archive**
3. Wait 5-10 minutes
4. Organizer opens → Click **"Distribute App"**
5. Select:
   - App Store Connect → Upload → Next
   - Automatically manage signing → Next
   - Review & **Upload**
6. Wait 15-30 minutes for processing

✅ Email confirmation when done!

---

### Step 6: App Store Connect Listing (30 minutes)

**Go to:** https://appstoreconnect.apple.com

**Create App:**
- My Apps → "+" → New App
- Platform: iOS
- Name: **StepOut**
- Language: English (U.S.)
- Bundle ID: com.stepout2.app
- SKU: stepout-ios-001

**Fill Required Info:**

**App Information:**
- Name: `StepOut - Events & Friends`
- Subtitle: `Organize and discover events with friends`
- Privacy Policy URL: [Your URL from Step 1]

**Categories:**
- Primary: Social Networking
- Secondary: Lifestyle

**Pricing:** Free

**Screenshots:**
- Upload 5 screenshots from Step 3
- For "6.7-inch Display"

**Description:**
```
StepOut makes it easy to create, discover, and attend events with your friends.

KEY FEATURES:
• Create Events - Quick event creation with photos, locations, and categories
• Smart Discovery - Find events by category, location, or search
• Friend Network - See what friends are attending and invite them
• Real-Time Updates - Get notified when friends RSVP or events change
• Event Categories - Sports, Food, Study, Party, Gaming, Outdoor, Music
• Privacy Controls - Keep events private or share publicly
• Calendar Integration - Track attended events in your profile

PERFECT FOR:
• College students organizing study groups
• Friend groups planning activities
• Sports teams coordinating games
• Food lovers discovering restaurants
• Anyone who wants quality time with friends

Download StepOut and start making memories!
```

**Keywords:**
```
events,friends,social,hangout,meetup,party,study,sports,food,calendar,organize
```

**Demo Account (CRITICAL):**
```
Username: demo@stepout.app
Password: StepOut2025!

TESTING INSTRUCTIONS:
1. Sign in with demo account
2. View Events tab
3. Create test event with + button
4. Search and filter events
5. View Profile calendar

Note: Uses Firebase. All features work with demo account.
```

**Age Rating:** Complete questionnaire → 12+

**Add Build:**
- Scroll to "Build" section
- Click "+" → Select your uploaded build
- Export compliance: YES to encryption, YES to exempt (HTTPS only)

---

### Step 7: Submit for Review

1. Review all fields are filled
2. Click **"Add for Review"** (top right)
3. Click **"Submit to App Review"**
4. Wait for confirmation email

**Review time:** Typically 24-48 hours

---

## 📞 Important Info

**Demo Account:**
```
Email: demo@stepout.app
Password: StepOut2025!
```

**Bundle ID:** `com.stepout2.app`

**Version:** 1.0 (Build 1)

**Privacy Policy URL:** [Add after hosting]

---

## ⏱ Time Estimate

- Privacy policy: 10 min
- Demo account: 5 min
- Screenshots: 20 min
- Xcode setup: 5 min
- Archive: 30 min
- App Store listing: 30 min

**Total:** ~2 hours

---

## 🆘 Common Issues

**"No signing identity"**
→ Xcode → Preferences → Accounts → Download Manual Profiles

**"Build failed"**
→ Clean (Cmd+Shift+K), then rebuild

**"Archive grayed out"**
→ Select "Any iOS Device (arm64)", not simulator

**"Upload failed"**
→ Check version/build number set correctly

---

## ✅ Pre-Submit Checklist

- [ ] Privacy policy hosted and URL saved
- [ ] Demo account created and tested
- [ ] 5 screenshots taken and saved
- [ ] Xcode signing configured
- [ ] Build archived successfully
- [ ] All App Store Connect fields filled
- [ ] Demo credentials in "Notes for Review"
- [ ] Tested app doesn't crash
- [ ] No placeholder text visible

---

## 🎉 After Submission

**Status Changes:**
1. "Waiting for Review" - In queue
2. "In Review" - Apple testing (24-48 hrs)
3. "Approved" - Goes live! 🎊
4. "Rejected" - Fix issues, resubmit

Most apps approved within 2-3 submissions if rejected.

---

**You've got this! 🚀**

Need help with any step? Just ask!
