# PropFirm - Premium Trading Challenge Website

A fully responsive, premium website for a proprietary trading firm built with modern web technologies. Features a dark theme with gold accents, smooth animations, and comprehensive trading challenge information.

## 🌟 Features

### Design & UI
- **Dark Modern Theme**: #0d0d0d background with gold (#FFD700) accents
- **Responsive Design**: Fully optimized for mobile and desktop
- **Premium Animations**: Smooth scroll, hover effects, and text animations
- **Professional Typography**: Poppins font family throughout
- **Loading Animation**: Custom loader with spinning gold accent

### Pages & Functionality
- **Homepage**: Hero section with animated tagline and about section
- **Funding Plans**: Three challenge types (Rapid Start, Pro Trader, Elite Challenge)
- **Rules Page**: Comprehensive trading guidelines and evaluation criteria
- **FAQ**: 8 detailed questions and answers with accordion interface
- **Contact**: Contact form, support information, and live chat placeholder
- **Authentication**: Login/signup modals ready for Firebase integration

### Interactive Features
- **Responsive Navigation**: Hamburger menu for mobile devices
- **Plan Selection Modal**: Detailed plan information with platform selection
- **Form Validation**: Real-time validation for all forms
- **Smooth Scrolling**: Enhanced user experience with scroll animations
- **Ripple Effects**: Material Design-inspired button interactions

## 🚀 Quick Start

### Local Development
1. Clone or download the repository
2. Open `index.html` in your web browser
3. No build process required - pure HTML, CSS, and JavaScript

### Live Server (Recommended)
```bash
# If you have Python installed
python -m http.server 8000

# If you have Node.js installed
npx serve .

# If you have PHP installed
php -S localhost:8000
```

Then visit `http://localhost:8000`

## 📁 Project Structure

```
propfirm-website/
├── index.html          # Homepage
├── funding.html        # Funding plans page
├── rules.html          # Trading rules page
├── faq.html           # FAQ page
├── contact.html       # Contact page
├── style.css          # Main stylesheet
├── script.js          # JavaScript functionality
└── README.md          # This file
```

## 🎨 Design System

### Colors
- **Primary Background**: #0d0d0d (Dark Black)
- **Secondary Background**: #111111 (Lighter Black)
- **Accent Color**: #FFD700 (Gold)
- **Text Primary**: #ffffff (White)
- **Text Secondary**: #cccccc (Light Gray)
- **Success**: #4CAF50 (Green)
- **Error**: #f44336 (Red)

### Typography
- **Font Family**: Poppins (Google Fonts)
- **Weights**: 300, 400, 500, 600, 700

## 📱 Responsive Breakpoints

- **Desktop**: 1200px and above
- **Tablet**: 768px to 1199px
- **Mobile**: 767px and below
- **Small Mobile**: 480px and below

## 🔧 Integration Ready

### Stripe Payments
The website includes placeholders for Stripe integration:
- Plan selection modal with payment button
- Platform selection (MT4/MT5)
- Fee calculation and display
- Ready for Stripe Checkout implementation

```javascript
// Example Stripe integration point
function proceedToPayment() {
    // Current implementation shows alert
    // Replace with Stripe checkout
    stripe.redirectToCheckout({
        sessionId: 'session_id_from_backend'
    });
}
```

### Firebase Authentication
Login and signup modals are prepared for Firebase:
- Form validation included
- User data collection ready
- Modal state management implemented

```javascript
// Example Firebase integration
import { auth } from './firebase-config.js';
import { signInWithEmailAndPassword } from 'firebase/auth';

function handleLogin(email, password) {
    signInWithEmailAndPassword(auth, email, password)
        .then((userCredential) => {
            // Handle successful login
        });
}
```

### Live Chat Integration
Placeholder for chat services like Intercom, Zendesk, or Crisp:
```javascript
function openLiveChat() {
    // Replace with your chat service
    Intercom('show');
}
```

## 🚀 Deployment

### Vercel (Recommended)
1. Push code to GitHub repository
2. Connect repository to Vercel
3. Deploy automatically

### Netlify
1. Drag and drop the project folder to Netlify
2. Or connect via GitHub for continuous deployment

### Traditional Hosting
Upload all files to your web server's public directory.

### GitHub Pages
1. Push to GitHub repository
2. Enable GitHub Pages in repository settings
3. Select source branch

## 📋 Checklist for Production

### Before Going Live
- [ ] Replace placeholder contact email
- [ ] Update office address information
- [ ] Integrate Stripe for payments
- [ ] Set up Firebase authentication
- [ ] Add live chat service
- [ ] Configure email service for contact form
- [ ] Add Google Analytics
- [ ] Set up SSL certificate
- [ ] Test all forms and functionality
- [ ] Optimize images and assets

### SEO Optimization
- [ ] Add meta descriptions to all pages
- [ ] Include Open Graph tags
- [ ] Add structured data markup
- [ ] Create sitemap.xml
- [ ] Add robots.txt
- [ ] Optimize page loading speed

## 🛠 Customization

### Adding New Plans
1. Update the pricing tables in `funding.html`
2. Add new plan logic in `script.js` (`getPlanName` function)
3. Update plan details modal content

### Styling Changes
- Main colors are defined as CSS custom properties
- Component styles are modular and easy to modify
- Responsive breakpoints can be adjusted in media queries

### Adding New Pages
1. Create new HTML file following existing structure
2. Add navigation link to all pages
3. Update active states in JavaScript

## 🔍 Browser Support

- Chrome 60+
- Firefox 60+
- Safari 12+
- Edge 79+
- Mobile browsers (iOS Safari, Chrome Mobile)

## 📞 Support

For questions or support regarding this website template:
- Check the FAQ section for common questions
- Review the code comments for implementation details
- Ensure all dependencies are properly loaded

## 📄 License

This website template is created for PropFirm. All rights reserved.

---

**Built with ❤️ for PropFirm - Trade. Grow. Get Funded.**
