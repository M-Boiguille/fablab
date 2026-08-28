let data = {};
let currentStack = '';

async function loadData() {
    try {
        const response = await fetch('data.json');
        data = await response.json();
        populateStackSelector();
    } catch (e) {
        console.error('Erreur de chargement des donnees', e);
    }
}

function populateStackSelector() {
    const selector = document.getElementById('stack-selector');
    selector.innerHTML = '<option value="" disabled selected>Choisir une stack</option>';
    const stacks = Object.keys(data.stacks || {});
    stacks.forEach(name => {
        const option = document.createElement('option');
        option.value = name;
        option.textContent = name;
        selector.appendChild(option);
    });

    if (stacks.length > 0) {
        currentStack = stacks[0];
        selector.value = currentStack;
        document.title = `Learning Platform - ${currentStack}`;
        renderBoard();
        updateProgress();
    }
}

function findPr(stepNum) {
    const stackData = data.stacks?.[currentStack];
    if (!stackData) return null;
    return (stackData.pull_requests || []).find(p => p.step === stepNum) || null;
}

function renderBoard() {
    const stackData = data.stacks?.[currentStack];
    if (!stackData) return;

    const steps = stackData.roadmap?.steps || [];
    const state = stackData.state || {};
    const currentStep = state.current_step || 0;
    const status = state.status || 'not_started';

    ['todo', 'inprogress', 'review', 'done'].forEach(id => {
        document.getElementById(id + '-list').innerHTML = '';
    });

    steps.forEach((step) => {
        const stepNum = step.step;
        const card = document.createElement('div');
        card.className = 'card';
        card.dataset.step = stepNum;

        const pr = findPr(stepNum);
        let column = 'todo';
        if (status === 'completed' || stepNum < currentStep) {
            column = 'done';
        } else if (pr) {
            column = 'review';
        } else if (stepNum === currentStep) {
            column = 'in-progress';
        }

        card.classList.add(column === 'done' ? 'done' : column === 'in-progress' ? 'in-progress' : column === 'review' ? 'review' : '');

        card.innerHTML = `
            <div class="step-number">Etape ${stepNum}</div>
            <div class="step-title">${step.title}</div>
            <div class="step-status">${step.description?.substring(0, 60) || ''}...</div>
        `;

        card.addEventListener('click', () => openModal(stepNum));
        document.getElementById(column + '-list').appendChild(card);
    });
}

function updateProgress() {
    const stackData = data.stacks?.[currentStack];
    if (!stackData) return;

    const total = stackData.roadmap?.total_steps || 1;
    const current = stackData.state?.current_step || 0;
    const status = stackData.state?.status || 'not_started';

    let pct = 0;
    if (status === 'completed') {
        pct = 100;
    } else {
        pct = Math.round((current / total) * 100);
    }
    document.getElementById('progress-badge').textContent = pct + '%';
}

function openModal(stepNum) {
    const stackData = data.stacks?.[currentStack];
    if (!stackData) return;

    const step = stackData.roadmap?.steps?.find(s => s.step === stepNum);
    if (!step) return;

    const state = stackData.state || {};
    const pr = findPr(stepNum);
    const modal = document.getElementById('modal');
    const body = document.getElementById('modal-body');

    body.innerHTML = `
        <h2>Etape ${stepNum} : ${step.title}</h2>
        <p><strong>Description :</strong> ${step.description || ''}</p>
        ${pr ? `<p><strong>PR en review :</strong> <a href="${pr.html_url}" target="_blank">#${pr.number} - ${pr.title}</a></p>` : ''}
        <hr>
        <h3>Contexte</h3>
        <p>${state.context_capsule || 'Aucune capsule de contexte disponible.'}</p>
        <h3>Decisions cles</h3>
        <ul>${(state.key_decisions || []).map(d => `<li>${d}</li>`).join('') || '<li>Aucune</li>'}</ul>
        <h3>Risques en attente</h3>
        <ul>${(state.pending_risks || []).map(r => `<li>${r}</li>`).join('') || '<li>Aucun</li>'}</ul>
    `;

    modal.style.display = 'block';
}

document.querySelector('.close').addEventListener('click', () => {
    document.getElementById('modal').style.display = 'none';
});
window.addEventListener('click', (e) => {
    if (e.target === document.getElementById('modal')) {
        document.getElementById('modal').style.display = 'none';
    }
});

document.getElementById('stack-selector').addEventListener('change', (e) => {
    currentStack = e.target.value;
    document.title = `Learning Platform - ${currentStack}`;
    renderBoard();
    updateProgress();
});

loadData();
