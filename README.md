# Lampo

**L'intelligenza del tuo Mac, a una scorciatoia di distanza. Sul tuo testo, sul tuo schermo, nelle tue app.**

Lampo vive nella barra dei menu e porta il modello di Apple che gira sul tuo Mac dove serve:
sul testo che hai selezionato, sulla finestra che stai guardando, su quello che hai copiato.
Selezioni, premi un tasto, il testo cambia al suo posto.

![Il pannello Vetro: una domanda, la risposta in streaming, il badge "Sul Mac"](docs/media/vetro.gif)

> *In English:* Lampo is a menu bar app that brings Apple's on-device model to your context: the text
> you select in any app, the window in front of you, your clipboard. Fast, offline, free and private.
> The app is in English and Italian.

## Perché Lampo

1. **Velocissimo.** Si apre in un istante e risponde subito, senza attese di rete né caricamenti.
2. **Funziona offline.** In treno, in aereo, senza Wi-Fi: il modello è già sul tuo Mac.
3. **Gratis, per sempre.** Nessun abbonamento, nessun limite di richieste, nessuna chiave API, nessun account.
4. **Privato per davvero.** Quello che scrivi e selezioni non lascia il Mac. Il cloud privato di Apple
   si usa solo quando lo chiedi tu, e Lampo te lo dice sempre.
5. **Lavora dove sei.** Selezioni, premi un tasto, il testo cambia al suo posto. Nessun copia-incolla in una chat.
6. **Vede quello che vedi.** Chiedi spiegazioni su qualsiasi finestra: un errore, un grafico, un modulo.
7. **Su misura.** Crea azioni personali, ognuna con la sua scorciatoia e il suo prompt.
8. **Nativo e leggero.** Fatto per macOS, discreto nella barra dei menu, consumi minimi.

## Come si usa

### Vetro: chiedi da qualsiasi app

Premi **⌥⇧Spazio**: il pannello si apre sopra l'app che stai usando, senza toglierle il controllo.
Scrivi una domanda e la risposta arriva in streaming. Se hai selezionato del testo, Lampo lo aggiunge
come contesto. Poi puoi copiare (⌘C), inserire la risposta nell'app sotto (⌘↩), fare una domanda di
seguito o chiedere di approfondire. I calcoli ("12 * 3,5") li fa Lampo stesso, senza modello.

### Lente: riscrivi dove sei

Seleziona un testo in qualsiasi app e premi la scorciatoia di un'azione. La Lente mostra l'anteprima
accanto alla selezione; ↩ sostituisce il testo al suo posto e ⌘Z lo riporta com'era. Tab passa
all'azione successiva. Gli appunti restano quelli che avevi.

- **Riscrivi** (⌥⇧R) ha quattro toni nella Lente: più chiaro, formale, amichevole, più breve.
  Lampo ricorda l'ultimo che hai scelto.
- **Traduci** (⌥⇧T) usa la Traduzione di Apple, non il modello: è più precisa, gira sul Mac e
  funziona anche senza Apple Intelligence. Traduce nella tua lingua; se il testo è già nella tua
  lingua, lo traduce in quella che hai scelto l'ultima volta. Nella Lente puoi cambiare lingua.
  Le lingue si scaricano in Impostazioni di Sistema › Generali › Lingua e Zona › Lingue di traduzione.

**Rispetto agli Strumenti di scrittura di Apple:** correggere e riscrivere li fa anche macOS, ma
dal menu contestuale e solo nelle app che li supportano. Lampo li mette a un tasto di distanza e
funziona anche in Chrome, Slack, VS Code e nelle altre app Electron. Per questo "Più formale",
"Più breve" e "Riassumi" sono spente di default (Riscrivi le copre): puoi riaccenderle in
Impostazioni › Azioni.

<!-- GIF da registrare: docs/media/lente.gif (vedi docs/media/README.md) -->

| Azione | Scorciatoia |
|---|---|
| Apri Lampo | ⌥⇧Spazio |
| Correggi | ⌥⇧C |
| Riscrivi | ⌥⇧R |
| Traduci | ⌥⇧T |
| Rispondi | ⌥⇧M |
| Detta | ⌥⇧D (tieni premuto, o premi due volte) |
| Chiedi allo schermo | ⌥⇧S |
| Crea evento | ⌥⇧E |
| Crea promemoria | ⌥⇧P |
| Estrai | ⌥⇧X |

Ogni scorciatoia si cambia in Impostazioni › Scorciatoie. In Impostazioni › Azioni puoi accendere o
spegnere le azioni, modificarle, crearne di nuove con il tuo prompt (o con la Traduzione di Apple verso
una lingua fissa, per esempio "Traduci in tedesco") e provarle su un testo di esempio. Ogni azione può
mostrare l'anteprima, sostituire subito il testo, copiarlo o aprire la risposta nel pannello.

### Rispondi

Seleziona un'email o un messaggio e premi **⌥⇧M**: Lampo scrive una bozza di risposta nella lingua del
messaggio, senza firma e senza inventare date o promesse. Nel pannello puoi cambiarla scrivendo in
italiano ("più breve", "di' che giovedì alle 15 va bene"): la risposta resta nella lingua del messaggio.
⌘C la copia, ⌘↩ la scrive dove c'è il cursore (mai sopra il messaggio selezionato).

### Detta e sistema

Tieni premuto **⌥⇧D** e parla, poi rilascia: Lampo trascrive sul Mac, toglie le esitazioni ("ehm",
"uhm"), mette la punteggiatura e scrive il testo dove c'è il cursore, in qualsiasi app (⌘Z lo toglie).
Per dettature lunghe premi ⌥⇧D una volta, parla, e premilo di nuovo per finire. Esc annulla.

- Il riconoscimento vocale è quello di Apple e gira sul Mac: serve solo il permesso del Microfono, e
  Lampo ascolta solo mentre detti. Il modello vocale si scarica una volta da Apple, solo se lo confermi
  (Impostazioni › Generali › Dettatura, dove scegli anche la lingua).
- Il modello piccolo di Apple sistema il testo cambiandolo il meno possibile. Se non è disponibile, o la
  dettatura è molto lunga, Lampo inserisce il testo così come l'hai detto.
- Puoi creare azioni tue con "Input: Dettatura": per esempio "Detta un'email" con il tuo prompt, oppure
  con risultato "Crea un evento" per dire "cena con Marco giovedì alle 20" e ritrovarti la scheda.

### Chiedi allo schermo

**⌥⇧S** fotografa solo la finestra che stai usando (mai Lampo stesso, mai il resto dello schermo) e
apre il pannello pronto per la domanda: "cosa significa questo errore?", "riassumi questa pagina".
Il Mac legge anche il testo della finestra (riconoscimento del testo di Apple, sul Mac) e lo manda
insieme all'immagine, così codici, cifre e scritte piccole arrivano esatti.

<!-- GIF da registrare: docs/media/schermo.gif (vedi docs/media/README.md) -->

### Crea evento e Crea promemoria

Seleziona "cena con Marco giovedì alle 20" (o un'email con data e ora) e premi **⌥⇧E**: Lampo
prepara l'evento con giorno, ora, luogo e titolo. **Non aggiunge nulla finché non confermi**: tutto è
modificabile nella scheda. Per gli eventi Lampo chiede solo il permesso di scrittura, quindi non può
leggere i tuoi calendari. **⌥⇧P** fa lo stesso con i Promemoria.

Un elenco diventa più voci in una sola scheda: "latte, chiamare Luca domani, bolletta venerdì" dà tre
promemoria, ognuno con la sua data. Togli la spunta a quelli che non vuoi e conferma una volta.

### Estrai

Seleziona un testo e premi **⌥⇧X**: Lampo capisce cosa contiene e lo mette in una scheda.

- **Contatto** (una firma email): nome, azienda, telefoni, email, indirizzo. "Aggiungi a Contatti" lo
  apre in Contatti, che chiede conferma: Lampo non legge né modifica la tua rubrica.
- **Tabella** (righe di dati): "Copia" la incolla come celle in Numbers o Excel; c'è anche "Copia come
  Markdown".
- **Cose da fare** (un'email con richieste): diventano promemoria da confermare, con le scadenze.

Se Lampo sceglie il tipo sbagliato, cambialo in alto nella scheda. Senza Apple Intelligence usa regole
semplici (numeri di telefono, email, colonne separate) e te lo dice.

![La scheda di conferma di "Crea evento"](docs/media/crea-evento.png)

### Comandi Rapidi e link

- In **Comandi Rapidi** trovi "Chiedi a Lampo" (restituisce la risposta) ed "Esegui azione Lampo"
  (esegue un'azione su un testo e restituisce il risultato).
- Il link **`lampo://ask?q=…`** apre il pannello e fa la domanda, per esempio da Raycast, Alfred o un
  segnalibro: `lampo://ask?q=Che%20ore%20sono%20a%20Tokyo%20se%20qui%20sono%20le%2015`.
  Un link non può eseguire azioni né modificare testo.

## Privacy

- Le richieste girano sul modello di Apple **sul tuo Mac**. Un badge dice sempre dove ha girato ogni risposta.
- **Private Cloud Compute** (il cloud privato di Apple) si usa solo quando premi "Pensa di più", nelle
  versioni che lo includono (richiede un'autorizzazione di Apple). Con **Solo sul Mac** attivo non si usa mai.
- Lampo va online solo per **controllare gli aggiornamenti** (Sparkle), e solo se lo consenti.
  Nessuna telemetria, nessun account, nessun dato di sistema inviato.
- La **cronologia** è spenta di default. Se la accendi resta solo sul Mac
  (`~/Library/Application Support/Lampo/history.json`) e spegnerla la cancella.
- Permessi: Accessibilità (leggere e sostituire la selezione), Registrazione schermo (solo per
  "Chiedi allo schermo"), Microfono (solo mentre detti), Calendari e Promemoria (solo quando confermi
  un evento o un promemoria). Nessun accesso ai Contatti: un contatto estratto passa a Contatti, che
  chiede conferma.
- La dettatura gira sul Mac. L'unico download è il modello vocale di Apple, una volta e solo se confermi.

## Cosa non fa

- **Non è un motore di ricerca né un'enciclopedia.** Il modello sul Mac è piccolo: è bravo a
  riscrivere, riassumere, tradurre, estrarre e spiegare quello che ha davanti, non a ricordare fatti.
  Per date, nomi e numeri controlla sempre la fonte.
- Non naviga sul web e non legge i tuoi file, le tue email o i tuoi calendari.
- Non sostituisce un testo troppo lungo: se deve usarne un estratto, te lo dice e ti lascia solo copiare.

## Requisiti

- macOS 27 su Mac con Apple silicon
- Apple Intelligence attiva (Impostazioni di Sistema › Apple Intelligence e Siri)

## Installazione

Scarica l'ultima versione dalla pagina delle release, oppure con Homebrew (dal tap del progetto):

```bash
brew install --cask lampo
```

Al primo avvio una guida passo passo, al centro dello schermo, spiega cosa fa Lampo e le sue scorciatoie,
poi chiede i permessi uno alla volta (Accessibilità, Registrazione schermo, Microfono, Calendari e Promemoria)
e qualche preferenza. Finché la guida è aperta Lampo ha un'icona nel Dock: se la finestra finisce dietro
Impostazioni di Sistema, un clic sull'icona la riporta davanti (torna davanti anche da sola quando concedi un
permesso). Se Lampo si riavvia, la guida riparte dal passo in cui eri; si riapre dal menu › Guida di benvenuto.

Lampo è in inglese; puoi passare all'italiano nel primo passo della guida o in Impostazioni › Generali › Lingua
(Lampo si riavvia). La lingua delle risposte, della traduzione e della dettatura segue comunque il Mac.

## Sviluppo

Serve Xcode 27 e [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
```

```bash
xcodebuild -project Lampo.xcodeproj -scheme Lampo -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages test
```

Convenzioni, comandi e decisioni: [CLAUDE.md](CLAUDE.md) e [docs/DECISIONS.md](docs/DECISIONS.md).
Checklist manuale: [docs/MANUAL_QA.md](docs/MANUAL_QA.md).

### Pubblicare una versione

`scripts/release.sh` esegue i test, archivia con la firma Developer ID, notarizza, crea lo zip,
l'appcast di Sparkle e il cask Homebrew. Una tantum:

1. Un certificato "Developer ID Application" nel portachiavi.
2. Le credenziali del servizio di notarizzazione:
   `xcrun notarytool store-credentials lampo-notary --apple-id <id> --team-id 9K3LNS3KHP`
3. La chiave EdDSA di Sparkle (resta nel portachiavi; il comando stampa la chiave pubblica):
   `build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys`
4. `cp Packaging/release.env.example Packaging/release.env` e compila URL del feed, prefisso dei
   download e chiave pubblica.

Poi:

```bash
scripts/release.sh
```

Per una prova locale senza notarizzazione: `scripts/release.sh --skip-notarize --skip-appcast`.
La versione è `MARKETING_VERSION` in `project.yml`; il numero di build è il numero di commit.
