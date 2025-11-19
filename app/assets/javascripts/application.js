// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, or any plugin's
// vendor/assets/javascripts directory can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// compiled file. JavaScript code in this file should be added after the last require_* statement.
//
// Read Sprockets README (https://github.com/rails/sprockets#sprockets-directives) for details
// about supported directives.
//
//= require rails-ujs
//= require activestorage
//= require turbolinks
//= require_tree .

document.addEventListener('DOMContentLoaded', () => {
  const mobileNavToggle = document.getElementById('mobile-nav-toggle');
  const mobileNavMenu = document.getElementById('mobile-nav-menu');
  const mobileNavClose = document.getElementById('mobile-nav-close');
  
  function closeMobileMenu() {
    mobileNavToggle.classList.remove('active');
    mobileNavMenu.classList.remove('active');
    document.body.style.overflow = '';
  }
  
  if (mobileNavToggle && mobileNavMenu) {
    mobileNavToggle.addEventListener('click', () => {
      mobileNavToggle.classList.toggle('active');
      mobileNavMenu.classList.toggle('active');
      
      if (mobileNavMenu.classList.contains('active')) {
        document.body.style.overflow = 'hidden';
      } else {
        document.body.style.overflow = '';
      }
    });
    
    if (mobileNavClose) {
      mobileNavClose.addEventListener('click', closeMobileMenu);
    }
    
    const mobileNavLinks = document.querySelectorAll('.mobile-nav-link');
    mobileNavLinks.forEach(link => {
      link.addEventListener('click', closeMobileMenu);
    });
    
    document.addEventListener('click', (e) => {
      if (!mobileNavToggle.contains(e.target) && !mobileNavMenu.contains(e.target)) {
        closeMobileMenu();
      }
    });
  }

  const hero = document.querySelector('.hero-main-section');
  if (hero && window.innerWidth > 991) {
    hero.addEventListener('mousemove', (e) => {
      const rect = hero.getBoundingClientRect();
      const x = (e.clientX - rect.left) / rect.width;
      const y = (e.clientY - rect.top) / rect.height;
      const tx = (x - 0.5) * 12;
      const ty = (y - 0.5) * 8; 
      hero.style.backgroundPosition = `${50 + tx}% ${50 + ty}%`;
    });

    hero.addEventListener('mouseleave', () => {
      hero.style.backgroundPosition = 'center';
    });
  }

  const form = document.getElementById('hero-main-form');
  if (form) {
    form.addEventListener('submit', (ev) => {
      ev.preventDefault();
      const btn = form.querySelector('.hero-main-submit');
      btn.disabled = true;
      btn.textContent = '送信中...';
      btn.style.opacity = '0.9';
      setTimeout(() => {
        btn.textContent = '送信しました';
        btn.style.background = '#0A8E4A';
      }, 1200);
    });
  }

});

document.querySelectorAll('.brand-track img').forEach(icon => {
  icon.addEventListener('mouseenter', () => {
    icon.style.transition = 'transform 0.3s ease';
    icon.style.transform = 'scale(1.1)';
  });
  icon.addEventListener('mouseleave', () => {
    icon.style.transform = 'scale(1)';
  });
});

(function(){
  const cards = document.querySelectorAll('.ser-mos-card');

  if ('IntersectionObserver' in window && cards.length) {
    const io = new IntersectionObserver((entries, obs) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          const el = entry.target;
          el.classList.add('inview');
          const children = el.querySelectorAll('.ser-mos-card-img, .ser-mos-card-title, .ser-mos-card-desc, .ser-mos-card-btn');
          children.forEach((ch, i) => {
            ch.style.transition = `transform .45s cubic-bezier(.2,.9,.3,1) ${i*80}ms, opacity .45s ${i*80}ms`;
            ch.style.opacity = '1';
            ch.style.transform = 'translateY(0)';
          });
          obs.unobserve(el);
        }
      });
    }, { threshold: 0.18 });

    cards.forEach(card => {
      card.querySelectorAll('.ser-mos-card-img, .ser-mos-card-title, .ser-mos-card-desc, .ser-mos-card-btn').forEach(ch=>{
        ch.style.opacity = '0';
        ch.style.transform = 'translateY(10px)';
      });
      io.observe(card);
    });
  } else {
    cards.forEach(c => c.classList.add('inview'));
  }
})();

(function(){
  const blocks = document.querySelectorAll('.main-moss-block');
  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver((entries, obs) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('inview');
          obs.unobserve(entry.target);
        }
      });
    }, { threshold: 0.2 });

    blocks.forEach(block => observer.observe(block));
  } else {
    blocks.forEach(block => block.classList.add('inview'));
  }
})();

document.querySelectorAll(".faq-japan-item").forEach((item) => {
  const question = item.querySelector(".faq-japan-question");

  question.addEventListener("click", () => {
    document.querySelectorAll(".faq-japan-item").forEach((faq) => {
      if (faq !== item) faq.classList.remove("active");
    });

    item.classList.toggle("active");
  });
});

if (typeof gsap !== "undefined") {
  gsap.utils.toArray(".faq-japan-item").forEach((el, i) => {
    gsap.from(el, {
      opacity: 0,
      y: 50,
      duration: 0.8,
      delay: i * 0.1,
      scrollTrigger: {
        trigger: el,
        start: "top 90%",
      },
    });
  });
}

if (typeof gsap !== "undefined") {
  gsap.utils.toArray(".cards-moos-card").forEach((card, i) => {
    gsap.from(card, {
      opacity: 0,
      y: 50,
      duration: 0.8,
      delay: i * 0.2,
      scrollTrigger: {
        trigger: card,
        start: "top 90%",
      },
    });
  });

  gsap.from(".cards-moos-btn", {
    opacity: 0,
    y: 40,
    duration: 1,
    scrollTrigger: {
      trigger: ".cards-moos-btn",
      start: "top 95%",
    },
  });
}

if (typeof gsap !== "undefined") {
  gsap.utils.toArray(".pricing-cards-card").forEach((card, i) => {
    gsap.from(card, {
      opacity: 0,
      y: 50,
      duration: 1,
      delay: i * 0.2,
      scrollTrigger: {
        trigger: card,
        start: "top 90%",
      },
    });
  });
}

document.addEventListener('DOMContentLoaded', function() {
  console.log('Initializing Swiper sliders...');
  
  const caseStudiesSwiper = new Swiper('.case-studies-swiper', {
    slidesPerView: 1,
    spaceBetween: 20,
    loop: true,
    autoplay: false,
    navigation: {
      nextEl: '.case-studies-next',
      prevEl: '.case-studies-prev',
    },
    pagination: {
      el: '.case-studies-pagination',
      clickable: true,
    },
    breakpoints: {
      768: {
        slidesPerView: 1,
        spaceBetween: 20,
      }
    }
  });
  
  const pricingSwiper = new Swiper('.pricing-swiper', {
    slidesPerView: 1,
    spaceBetween: 20,
    loop: true,
    autoplay: false,
    navigation: {
      nextEl: '.pricing-next',
      prevEl: '.pricing-prev',
    },
    pagination: {
      el: '.pricing-pagination',
      clickable: true,
    },
    breakpoints: {
      768: {
        slidesPerView: 1,
        spaceBetween: 20,
      }
    }
  });
  
  console.log('Swiper sliders initialized successfully!');
});

document.addEventListener('DOMContentLoaded', () => {
  const section = document.querySelector('.japan-notyo-section');

  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        section.classList.add('japan-notyo-visible');
        observer.unobserve(section);
      }
    });
  }, { threshold: 0.3 });

  observer.observe(section);
});

document.addEventListener('DOMContentLoaded', function() {
  
  const observerOptions = {
    root: null,
    rootMargin: '0px',
    threshold: 0.2
  };
  
  const observerCallback = (entries, observer) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('jap-notto-visible');
        
      }
    });
  };
  
  const observer = new IntersectionObserver(observerCallback, observerOptions);
  
  const heading = document.querySelector('.jap-notto-heading');
  if (heading) {
    observer.observe(heading);
  }
  
  const imageContainers = document.querySelectorAll('.jap-notto-image-container');
  imageContainers.forEach(container => {
    observer.observe(container);
  });
  
  const centerImage = document.querySelector('.jap-notto-center-image');
  if (centerImage) {
    observer.observe(centerImage);
  }
  
  setTimeout(() => {
    if (centerImage && centerImage.classList.contains('jap-notto-visible')) {
      centerImage.style.animation = 'jap-notto-float 3s ease-in-out infinite';
    }
  }, 2000);
  
});

const style = document.createElement('style');
style.textContent = `
  @keyframes jap-notto-float {
    0%, 100% {
      transform: translate(-50%, -50%) translateY(0px);
    }
    50% {
      transform: translate(-50%, -50%) translateY(-10px);
    }
  }
`;
document.head.appendChild(style);




const mountDataTargetNav = () => {
  document.body.addEventListener('click', (e) => {
    const a = e.target.closest('a[data-target]');
    if (!a) return;

    e.preventDefault();
    const id = a.getAttribute('data-target');
    const target = document.getElementById(id);
    if (!target) return;

    const headerH = document.querySelector('.site-header')?.offsetHeight || 0;
    const top = target.getBoundingClientRect().top + window.scrollY - headerH - 10;

    window.scrollTo({ top: Math.max(0, Math.round(top)), behavior: 'smooth' });

    // 擬似スクロールイベントでfadeIn系の再判定を促す
    setTimeout(() => window.dispatchEvent(new Event('scroll')), 60);
  });
};

if (window.Turbo) document.addEventListener('turbo:load', mountDataTargetNav);
else document.addEventListener('DOMContentLoaded', mountDataTargetNav);
