(function () {
  function fillFinal(el, text) {
    var finalEl = el.querySelector('[data-final-log]');
    if (!finalEl) return;
    var body = (text || '').toString();
    finalEl.textContent = body.length ? body : 'つながると、ここに会話が出ます。';
  }

  function bindOne(el) {
    if (!window.App || !App.cable) return;
    var callId = el.getAttribute('data-call-id');
    if (!callId || el.dataset.boundTranscript === callId) return;
    el.dataset.boundTranscript = callId;

    var interimEl = el.querySelector('[data-interim-line]');
    var confirmedEl = el.querySelector('[data-confirmed-log]');

    function appendConfirmed(text) {
      if (!confirmedEl) return;
      var line = '確定: ' + text;
      var current = confirmedEl.textContent || '';
      if (current.slice(-line.length) === line) return;
      confirmedEl.textContent = current ? (current + '\n' + line) : line;
      confirmedEl.style.display = '';
    }

    App.cable.subscriptions.create(
      { channel: 'CallTranscriptChannel', call_id: callId },
      {
        received: function (data) {
          if (!data || !data.text) return;
          if (data.interim || data.status === 'interim') {
            if (interimEl) {
              interimEl.textContent = '認識中: ' + data.text;
              interimEl.style.display = '';
            }
            return;
          }
          if (data.status === 'final') {
            appendConfirmed(data.text);
            if (interimEl) {
              interimEl.textContent = '';
              interimEl.style.display = 'none';
            }
            return;
          }
          if (interimEl) {
            interimEl.textContent = '';
            interimEl.style.display = 'none';
          }
          if (data.speaker === 'them' && confirmedEl) {
            confirmedEl.textContent = '';
          }
        }
      }
    );
  }

  function pollOne(el) {
    var url = el.getAttribute('data-poll-url');
    if (!url) return;

    fetch(url, { credentials: 'same-origin', headers: { Accept: 'application/json' } })
      .then(function (res) { return res.ok ? res.json() : null; })
      .then(function (payload) {
        if (!payload) return;
        var call = payload.watch_call;
        if (!call) return;
        if (call.id && String(el.getAttribute('data-call-id')) !== String(call.id)) {
          el.setAttribute('data-call-id', call.id);
        }
        fillFinal(el, call.speech_result);
        bindOne(el);
      })
      .catch(function () {});
  }

  function bindCallTranscripts() {
    document.querySelectorAll('[data-live-transcript]').forEach(function (el) {
      bindOne(el);
      pollOne(el);
      if (el.dataset.pollTimer === '1') return;
      el.dataset.pollTimer = '1';
      window.setInterval(function () { pollOne(el); }, 1000);
    });
  }

  document.addEventListener('turbolinks:load', bindCallTranscripts);
  document.addEventListener('DOMContentLoaded', bindCallTranscripts);
})();
