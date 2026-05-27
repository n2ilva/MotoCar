# MotoCar Android

Aplicativo Android em Flutter para apoiar motoristas na avaliacao de ofertas Uber e 99. O
app calcula `valor da oferta / (km ate o passageiro + km da viagem)`, compara
com os parametros do motorista e mantem dados somente no aparelho em SQLite.

## Funcoes implementadas

- Identificacao de `Uber` ou `99`, valor e duas distancias por OCR.
- Card verde para oferta aprovada e vermelho para oferta fora dos limites,
  destacando em tamanho maior o valor medio por km.
- Botao `ACEITEI - INICIAR TRAJETO` no card flutuante para registrar a
  corrida aceita e iniciar o GPS em um toque.
- Historico local das ofertas reconhecidas, aceitas e finalizadas.
- Eliminacao de solicitacoes repetidas com a mesma plataforma, valor e
  distancias; registros duplicados antigos sao consolidados na atualizacao.
- Parametros de distancia maxima ate passageiro, distancia da viagem e media
  minima esperada em `R$ / km`, exatamente como exibida no popup.
- Comparador de gasolina e etanol usando preco e rendimento do veiculo,
  incluindo manutencao/depreciacao no custo calculado por km.
- Medicao de distancia percorrida por GPS com FAB de play/pause dentro do app
  e bolha redonda sobre Uber/99, persistida em SQLite.
- Resultado diario com receita das corridas aceitas, km rodado, gasto de
  combustivel calculado e saldo apos combustivel.
- Tela principal mostrando somente ofertas do dia, com arquivo acessivel dos
  dias anteriores.
- Aba `Ganhos` com grafico dos ultimos 7 dias para receita e combustivel.
- Retencao automatica: ofertas e trajetos sao mantidos localmente por 15 dias.
- Leitura continua da tela autorizada pelo usuario, notificacao de captura
  ativa e pop flutuante por cima da oferta.

## Funcionamento Android

O botao **Iniciar leitura Uber / 99** pede permissao para desenhar
sobre outros apps e consentimento de captura via `MediaProjection`. O Android
exige novo consentimento quando uma sessao de captura for iniciada. Autorize
tambem a localizacao ao iniciar para habilitar a medicao flutuante de trajeto.
Enquanto a tela do proprio MotoCar estiver aberta, o OCR fica pausado
automaticamente e volta a analisar ao trocar para Uber ou 99.

Ao iniciar o monitor, uma bolha redonda `PLAY TRAJETO` fica disponivel sobre
Uber/99. Ela muda para `PAUSE`, exibe os quilometros percorridos e persiste a
sessao localmente enquanto o servico visivel esta ativo. A bolha pode ser
arrastada para qualquer posicao. Durante o arraste, solte-a sobre o `X`
vermelho na parte inferior da tela para encerrar a analise e fechar o MotoCar.

Quando uma oferta aparece, use `ACEITEI - INICIAR TRAJETO` no popup do MotoCar
e confirme o aceite no aplicativo Uber ou 99. O MotoCar nao toca
automaticamente no botao da plataforma: isso evita aceitar uma corrida errada
caso o layout ou a leitura OCR mude. Depois do aceite, a medicao inicia
automaticamente. Ao reconhecer uma tela de corrida concluida/resumo, ela e
pausada e finalizada; se a plataforma mostrar um texto diferente, toque em
`PAUSE` na bolha para concluir manualmente.

## Execucao

Requisitos: Flutter stable e Android SDK.

```bash
flutter pub get
flutter run
```

```bash
flutter build apk --debug
```

## Privacidade e publicacao

A captura e iniciada apenas apos autorizacao visivel do motorista; ofertas e
trajetos ficam no banco local `motocar.db`. Antes de distribuicao, acrescente
politica de privacidade/LGPD, exclusao/exportacao de dados, testes com
ofertas reais de diferentes versoes dos apps e confirme os termos de uso
de Uber/99 e as politicas da Google Play.

Referencias tecnicas:

- Android MediaProjection: <https://developer.android.com/media/grow/media-projection>
- Android overlays: <https://developer.android.com/reference/android/provider/Settings#canDrawOverlays(android.content.Context)>
