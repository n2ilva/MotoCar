# MotoCar Android

Aplicativo Android em Flutter para apoiar motoristas na avaliacao de ofertas Uber e 99. O
app calcula `valor da oferta / (km ate o passageiro + km da viagem)`, compara
com os parametros do motorista e mantem dados somente no aparelho em SQLite.

## Funcoes implementadas

- Identificacao de `UberX` como Uber; solicitacoes validas sem `UberX` sao
  classificadas como 99.
- Filtro de contexto do card para evitar reconhecer valores e distancias
  soltos do mapa como uma solicitacao, incluindo cards da 99 no formato
  `2min (596m)` e `9min (4,6km)`.
- Reconhecimento de distancias em km ou metros, sem usar o texto `R$ /km`
  como distancia de destino.
- Card verde para oferta aprovada e vermelho para oferta fora dos limites,
  destacando em tamanho maior o valor medio por km.
- Bolha flutuante `ACEITEI` para registrar a ultima oferta reconhecida.
- Historico local das ofertas reconhecidas e aceitas.
- Eliminacao de solicitacoes repetidas com a mesma plataforma, valor e
  distancias; registros duplicados antigos sao consolidados na atualizacao.
- Parametros de distancia maxima ate passageiro, distancia da viagem e media
  minima esperada em `R$ / km`, exatamente como exibida no popup.
- Comparador de gasolina e etanol usando preco e rendimento do veiculo,
  incluindo manutencao/depreciacao no custo calculado por km.
- Resultado diario com receita das corridas aceitas, km estimado pelas
  distancias das ofertas, gasto de combustivel calculado e saldo.
- Tela principal mostrando somente ofertas do dia, com arquivo acessivel dos
  dias anteriores.
- Aba `Ganhos` com grafico dos ultimos 7 dias para receita e combustivel.
- Retencao automatica: ofertas sao mantidas localmente por 15 dias.
- Leitura continua da tela autorizada pelo usuario, notificacao de captura
  ativa e pop flutuante por cima da oferta.

## Funcionamento Android

O botao **Iniciar leitura Uber / 99** pede permissao para desenhar
sobre outros apps e consentimento de captura via `MediaProjection`. O Android
exige novo consentimento quando uma sessao de captura for iniciada.
Enquanto a tela do proprio MotoCar estiver aberta, o OCR fica pausado
automaticamente e volta a analisar ao trocar para Uber ou 99.

Ao iniciar o monitor, uma bolha redonda `ACEITEI` fica disponivel sobre
Uber/99. Toque nela depois de aceitar uma oferta na plataforma para registrar
a corrida no MotoCar. A bolha pode ser
arrastada para qualquer posicao. Durante o arraste, solte-a sobre o `X`
vermelho na parte inferior da tela para encerrar a analise e fechar o MotoCar.

Quando uma oferta aparece, confirme o aceite no aplicativo Uber ou 99 e toque
na bolha `ACEITEI`. O MotoCar nao toca
automaticamente no botao da plataforma: isso evita aceitar uma corrida errada
caso o layout ou a leitura OCR mude. Para os calculos financeiros, o km rodado
e estimado pela soma de `km ate passageiro + km ate destino` de cada corrida
aceita.

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
configuracoes ficam no banco local `motocar.db`. Antes de distribuicao, acrescente
politica de privacidade/LGPD, exclusao/exportacao de dados, testes com
ofertas reais de diferentes versoes dos apps e confirme os termos de uso
de Uber/99 e as politicas da Google Play.

Referencias tecnicas:

- Android MediaProjection: <https://developer.android.com/media/grow/media-projection>
- Android overlays: <https://developer.android.com/reference/android/provider/Settings#canDrawOverlays(android.content.Context)>
