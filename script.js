// Global variables
let currentPlan = null;
let currentSize = null;
let currentFee = null;

// DOM Content Loaded
document.addEventListener('DOMContentLoaded', function() {
    initializeLoader();
    initializeNavigation();
    initializeAnimations();
    initializeForms();
    initializeFAQ();
    
    // Hide loader after 2 seconds
    setTimeout(() => {
        hideLoader();
    }, 2000);
});

// Loader Functions
function initializeLoader() {
    const loader = document.getElementById('loader');
    if (loader) {
        loader.style.display = 'flex';
    }
}

function hideLoader() {
    const loader = document.getElementById('loader');
    if (loader) {
        loader.classList.add('hidden');
        setTimeout(() => {
            loader.style.display = 'none';
        }, 500);
    }
}

// Navigation Functions
function initializeNavigation() {
    const hamburger = document.getElementById('hamburger');
    const navMenu = document.getElementById('nav-menu');
    
    if (hamburger && navMenu) {
        hamburger.addEventListener('click', function() {
            hamburger.classList.toggle('active');
            navMenu.classList.toggle('active');
        });
        
        // Close mobile menu when clicking on a link
        const navLinks = document.querySelectorAll('.nav-link');
        navLinks.forEach(link => {
            link.addEventListener('click', function() {
                hamburger.classList.remove('active');
                navMenu.classList.remove('active');
            });
        });
    }
    
    // Handle scroll effect on navbar
    window.addEventListener('scroll', function() {
        const navbar = document.querySelector('.navbar');
        if (navbar) {
            if (window.scrollY > 50) {
                navbar.style.background = 'rgba(13, 13, 13, 0.98)';
            } else {
                navbar.style.background = 'rgba(13, 13, 13, 0.95)';
            }
        }
    });
}

// Animation Functions
function initializeAnimations() {
    // Intersection Observer for fade-in animations
    const observerOptions = {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    };
    
    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.style.opacity = '1';
                entry.target.style.transform = 'translateY(0)';
            }
        });
    }, observerOptions);
    
    // Observe elements with fade-in class
    const fadeElements = document.querySelectorAll('.feature, .rule-card, .plan-card, .info-card, .support-item');
    fadeElements.forEach(el => {
        el.style.opacity = '0';
        el.style.transform = 'translateY(30px)';
        el.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
        observer.observe(el);
    });
}

// Modal Functions
function openLoginModal() {
    const modal = document.getElementById('loginModal');
    if (modal) {
        modal.classList.add('show');
        modal.style.display = 'flex';
        document.body.style.overflow = 'hidden';
    }
}

function closeLoginModal() {
    const modal = document.getElementById('loginModal');
    if (modal) {
        modal.classList.remove('show');
        modal.style.display = 'none';
        document.body.style.overflow = 'auto';
    }
}

function openSignupModal() {
    const modal = document.getElementById('signupModal');
    if (modal) {
        modal.classList.add('show');
        modal.style.display = 'flex';
        document.body.style.overflow = 'hidden';
    }
}

function closeSignupModal() {
    const modal = document.getElementById('signupModal');
    if (modal) {
        modal.classList.remove('show');
        modal.style.display = 'none';
        document.body.style.overflow = 'auto';
    }
}

function switchToSignup() {
    closeLoginModal();
    setTimeout(() => {
        openSignupModal();
    }, 100);
}

function switchToLogin() {
    closeSignupModal();
    setTimeout(() => {
        openLoginModal();
    }, 100);
}

// Plan Details Modal Functions
function openPlanDetails(plan, size, fee) {
    currentPlan = plan;
    currentSize = size;
    currentFee = fee;
    
    const modal = document.getElementById('planDetailsModal');
    const selectedPlan = document.getElementById('selectedPlan');
    const selectedSize = document.getElementById('selectedSize');
    const selectedFeeElement = document.getElementById('selectedFee');
    const tradingDaysRule = document.getElementById('tradingDaysRule');
    
    if (modal && selectedPlan && selectedSize && selectedFeeElement) {
        // Update plan details
        selectedPlan.textContent = getPlanName(plan);
        selectedSize.textContent = getSizeDisplay(size);
        selectedFeeElement.textContent = fee;
        
        // Update trading days rule based on plan
        if (tradingDaysRule) {
            switch(plan) {
                case 'rapid':
                    tradingDaysRule.textContent = 'Minimum trading days: 10';
                    break;
                case 'pro':
                    tradingDaysRule.textContent = 'Minimum trading days: 5 per phase';
                    break;
                case 'elite':
                    tradingDaysRule.textContent = 'Minimum trading days: 5 per phase';
                    break;
            }
        }
        
        modal.classList.add('show');
        modal.style.display = 'flex';
        document.body.style.overflow = 'hidden';
    }
}

function closePlanDetails() {
    const modal = document.getElementById('planDetailsModal');
    if (modal) {
        modal.classList.remove('show');
        modal.style.display = 'none';
        document.body.style.overflow = 'auto';
    }
}

function proceedToPayment() {
    // Placeholder for Stripe integration
    const selectedPlatform = document.querySelector('input[name="platform"]:checked')?.value || 'mt4';
    
    alert(`Proceeding to payment for:\n\nPlan: ${getPlanName(currentPlan)}\nSize: ${getSizeDisplay(currentSize)}\nFee: ${currentFee}\nPlatform: ${selectedPlatform.toUpperCase()}\n\nThis would integrate with Stripe for actual payments.`);
    
    // Close modal
    closePlanDetails();
}

function getPlanName(plan) {
    switch(plan) {
        case 'rapid': return 'Rapid Start';
        case 'pro': return 'Pro Trader';
        case 'elite': return 'Elite Challenge';
        default: return 'Unknown Plan';
    }
}

function getSizeDisplay(size) {
    switch(size) {
        case '5k': return '$5,000';
        case '10k': return '$10,000';
        case '25k': return '$25,000';
        case '50k': return '$50,000';
        case '100k': return '$100,000';
        default: return 'Unknown Size';
    }
}

// FAQ Functions
function initializeFAQ() {
    const faqQuestions = document.querySelectorAll('.faq-question');
    faqQuestions.forEach(question => {
        question.addEventListener('click', function() {
            const faqItem = this.parentElement;
            const isActive = faqItem.classList.contains('active');
            
            // Close all FAQ items
            document.querySelectorAll('.faq-item').forEach(item => {
                item.classList.remove('active');
            });
            
            // Open clicked item if it wasn't active
            if (!isActive) {
                faqItem.classList.add('active');
            }
        });
    });
}

function toggleFAQ(element) {
    const faqItem = element.parentElement;
    const isActive = faqItem.classList.contains('active');
    
    // Close all FAQ items
    document.querySelectorAll('.faq-item').forEach(item => {
        item.classList.remove('active');
    });
    
    // Open clicked item if it wasn't active
    if (!isActive) {
        faqItem.classList.add('active');
    }
}

// Form Functions
function initializeForms() {
    // Contact form
    const contactForm = document.getElementById('contactForm');
    if (contactForm) {
        contactForm.addEventListener('submit', handleContactForm);
    }
    
    // Auth forms
    const loginForm = document.querySelector('#loginModal .auth-form');
    const signupForm = document.querySelector('#signupModal .auth-form');
    
    if (loginForm) {
        loginForm.addEventListener('submit', handleLogin);
    }
    
    if (signupForm) {
        signupForm.addEventListener('submit', handleSignup);
    }
}

function handleContactForm(e) {
    e.preventDefault();
    
    const formData = new FormData(e.target);
    const data = {
        firstName: formData.get('firstName'),
        lastName: formData.get('lastName'),
        email: formData.get('email'),
        subject: formData.get('subject'),
        message: formData.get('message'),
        newsletter: formData.get('newsletter') === 'on'
    };
    
    // Simulate form submission
    console.log('Contact form submitted:', data);
    
    // Show success modal
    showSuccessModal();
    
    // Reset form
    e.target.reset();
}

function handleLogin(e) {
    e.preventDefault();
    
    const formData = new FormData(e.target);
    const data = {
        email: formData.get('email') || document.getElementById('loginEmail').value,
        password: formData.get('password') || document.getElementById('loginPassword').value
    };
    
    // Placeholder for Firebase authentication
    console.log('Login attempt:', data);
    alert('Login functionality will be integrated with Firebase. Demo credentials accepted.');
    
    closeLoginModal();
}

function handleSignup(e) {
    e.preventDefault();
    
    const formData = new FormData(e.target);
    const data = {
        name: formData.get('name') || document.getElementById('signupName').value,
        email: formData.get('email') || document.getElementById('signupEmail').value,
        password: formData.get('password') || document.getElementById('signupPassword').value
    };
    
    // Placeholder for Firebase authentication
    console.log('Signup attempt:', data);
    alert('Signup functionality will be integrated with Firebase. Account created successfully!');
    
    closeSignupModal();
}

function showSuccessModal() {
    const modal = document.getElementById('successModal');
    if (modal) {
        modal.classList.add('show');
        modal.style.display = 'flex';
        document.body.style.overflow = 'hidden';
    }
}

function closeSuccessModal() {
    const modal = document.getElementById('successModal');
    if (modal) {
        modal.classList.remove('show');
        modal.style.display = 'none';
        document.body.style.overflow = 'auto';
    }
}

// Live Chat Function
function openLiveChat() {
    alert('Live chat functionality would be integrated with a service like Intercom, Zendesk, or Crisp. This is a placeholder.');
}

// Close modals when clicking outside
window.addEventListener('click', function(e) {
    const modals = document.querySelectorAll('.modal');
    modals.forEach(modal => {
        if (e.target === modal) {
            modal.classList.remove('show');
            modal.style.display = 'none';
            document.body.style.overflow = 'auto';
        }
    });
});

// Handle escape key to close modals
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        const activeModals = document.querySelectorAll('.modal.show');
        activeModals.forEach(modal => {
            modal.classList.remove('show');
            modal.style.display = 'none';
            document.body.style.overflow = 'auto';
        });
    }
});

// Smooth scrolling for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            target.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
        }
    });
});

// Add loading states for buttons
function addLoadingState(button, originalText) {
    button.disabled = true;
    button.textContent = 'Loading...';
    
    setTimeout(() => {
        button.disabled = false;
        button.textContent = originalText;
    }, 2000);
}

// Enhanced button interactions
document.addEventListener('click', function(e) {
    if (e.target.classList.contains('btn-primary') || 
        e.target.classList.contains('btn-buy') ||
        e.target.classList.contains('cta-button')) {
        
        const originalText = e.target.textContent;
        addLoadingState(e.target, originalText);
    }
});

// Parallax effect for hero section
window.addEventListener('scroll', function() {
    const scrolled = window.pageYOffset;
    const hero = document.querySelector('.hero-background');
    if (hero) {
        hero.style.transform = `translateY(${scrolled * 0.5}px)`;
    }
});

// Add hover effects for cards
function initializeCardEffects() {
    const cards = document.querySelectorAll('.plan-card, .rule-card, .info-card, .feature');
    
    cards.forEach(card => {
        card.addEventListener('mouseenter', function() {
            this.style.transform = 'translateY(-10px)';
        });
        
        card.addEventListener('mouseleave', function() {
            this.style.transform = 'translateY(0)';
        });
    });
}

// Initialize card effects after DOM load
document.addEventListener('DOMContentLoaded', function() {
    setTimeout(initializeCardEffects, 100);
});

// Text animation for hero section
function initializeTextAnimations() {
    const animatedTexts = document.querySelectorAll('.animated-text');
    
    animatedTexts.forEach((text, index) => {
        text.style.animationDelay = `${index * 0.5}s`;
    });
}

// Initialize text animations
document.addEventListener('DOMContentLoaded', function() {
    initializeTextAnimations();
});

// Add ripple effect to buttons
function createRipple(event) {
    const button = event.currentTarget;
    const circle = document.createElement('span');
    const diameter = Math.max(button.clientWidth, button.clientHeight);
    const radius = diameter / 2;
    
    circle.style.width = circle.style.height = `${diameter}px`;
    circle.style.left = `${event.clientX - button.offsetLeft - radius}px`;
    circle.style.top = `${event.clientY - button.offsetTop - radius}px`;
    circle.classList.add('ripple');
    
    const ripple = button.getElementsByClassName('ripple')[0];
    if (ripple) {
        ripple.remove();
    }
    
    button.appendChild(circle);
}

// Add ripple effect to all buttons
document.addEventListener('DOMContentLoaded', function() {
    const buttons = document.querySelectorAll('.btn-primary, .btn-buy, .cta-button, .btn-login, .btn-signup');
    buttons.forEach(button => {
        button.addEventListener('click', createRipple);
    });
});

// Add CSS for ripple effect
const rippleCSS = `
.ripple {
    position: absolute;
    border-radius: 50%;
    transform: scale(0);
    animation: ripple 600ms linear;
    background-color: rgba(255, 215, 0, 0.3);
}

@keyframes ripple {
    to {
        transform: scale(4);
        opacity: 0;
    }
}
`;

// Inject ripple CSS
const style = document.createElement('style');
style.textContent = rippleCSS;
document.head.appendChild(style);

// Performance optimization: Throttle scroll events
function throttle(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

// Apply throttling to scroll events
const throttledScroll = throttle(function() {
    // Scroll-based animations and effects
    const scrolled = window.pageYOffset;
    
    // Parallax effect
    const hero = document.querySelector('.hero-background');
    if (hero) {
        hero.style.transform = `translateY(${scrolled * 0.3}px)`;
    }
    
    // Navbar background change
    const navbar = document.querySelector('.navbar');
    if (navbar) {
        if (scrolled > 50) {
            navbar.style.background = 'rgba(13, 13, 13, 0.98)';
        } else {
            navbar.style.background = 'rgba(13, 13, 13, 0.95)';
        }
    }
}, 16);

window.addEventListener('scroll', throttledScroll);

// Add page transition effects
function initializePageTransitions() {
    // Fade in page content
    document.body.style.opacity = '0';
    document.body.style.transition = 'opacity 0.5s ease';
    
    window.addEventListener('load', function() {
        document.body.style.opacity = '1';
    });
}

// Initialize page transitions
initializePageTransitions();

// Add form validation
function validateEmail(email) {
    const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return re.test(email);
}

function validateForm(form) {
    const inputs = form.querySelectorAll('input[required], select[required], textarea[required]');
    let isValid = true;
    
    inputs.forEach(input => {
        if (!input.value.trim()) {
            input.style.borderColor = '#f44336';
            isValid = false;
        } else if (input.type === 'email' && !validateEmail(input.value)) {
            input.style.borderColor = '#f44336';
            isValid = false;
        } else {
            input.style.borderColor = '#333';
        }
    });
    
    return isValid;
}

// Enhanced form handling with validation
document.addEventListener('DOMContentLoaded', function() {
    const forms = document.querySelectorAll('form');
    
    forms.forEach(form => {
        form.addEventListener('submit', function(e) {
            if (!validateForm(this)) {
                e.preventDefault();
                alert('Please fill in all required fields correctly.');
            }
        });
        
        // Real-time validation
        const inputs = form.querySelectorAll('input, select, textarea');
        inputs.forEach(input => {
            input.addEventListener('blur', function() {
                if (this.hasAttribute('required') && !this.value.trim()) {
                    this.style.borderColor = '#f44336';
                } else if (this.type === 'email' && this.value && !validateEmail(this.value)) {
                    this.style.borderColor = '#f44336';
                } else {
                    this.style.borderColor = '#333';
                }
            });
            
            input.addEventListener('focus', function() {
                this.style.borderColor = '#FFD700';
            });
        });
    });
});

// Console welcome message
console.log('%c🚀 PropFirm Website Loaded Successfully!', 'color: #FFD700; font-size: 16px; font-weight: bold;');
console.log('%cReady for Firebase integration and Stripe payments.', 'color: #cccccc; font-size: 12px;');