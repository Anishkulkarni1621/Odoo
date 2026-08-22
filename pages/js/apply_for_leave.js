// Mobile navigation scroll behavior and leave duration interaction.
let lastScrollY = window.scrollY;
const mobileNav = document.getElementById('mobile-nav');

window.addEventListener('scroll', () => {
    if (window.innerWidth < 768 && mobileNav) {
        mobileNav.style.transform = window.scrollY > lastScrollY && window.scrollY > 50
            ? 'translateY(100%)'
            : 'translateY(0)';
    }
    lastScrollY = window.scrollY;
}, { passive: true });

const startDate = document.getElementById('start_date');
const endDate = document.getElementById('end_date');

function updateDuration() {
    if (startDate.value && endDate.value) {
        const start = new Date(startDate.value);
        const end = new Date(endDate.value);
        if (end >= start) {
            const durationBox = document.querySelector('.bg-blue-50');
            if (durationBox) {
                durationBox.style.transform = 'scale(1.02)';
                setTimeout(() => {
                    durationBox.style.transform = 'scale(1)';
                }, 200);
            }
        }
    }
}

startDate.addEventListener('change', updateDuration);
endDate.addEventListener('change', updateDuration);