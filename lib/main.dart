import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models/offer.dart';
import 'services/app_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MotoCarApp());
}

class MotoCarApp extends StatefulWidget {
  const MotoCarApp({super.key});

  @override
  State<MotoCarApp> createState() => _MotoCarAppState();
}

class _MotoCarAppState extends State<MotoCarApp> {
  late final AppController controller;

  @override
  void initState() {
    super.initState();
    controller = AppController()..initialise();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'MotoCar',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF126B53),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF101715),
      cardTheme: const CardThemeData(color: Color(0xFF18221F)),
    ),
    home: HomePage(controller: controller),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;
  RideOffer? shownOffer;

  AppController get controller => widget.controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.loading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      _surfaceEvents();
      final pages = [
        Dashboard(controller: controller),
        ReportsPage(controller: controller),
        ParametersPage(controller: controller),
        VehicleCostPage(controller: controller),
      ];
      return Scaffold(
        appBar: AppBar(title: const Text('MotoCar')),
        body: pages[index],
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (selected) => setState(() => index = selected),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.route_outlined),
              label: 'Corridas',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              label: 'Ganhos',
            ),
            NavigationDestination(icon: Icon(Icons.tune), label: 'Parametros'),
            NavigationDestination(
              icon: Icon(Icons.local_gas_station_outlined),
              label: 'Custos',
            ),
          ],
        ),
      );
    },
  );

  void _surfaceEvents() {
    if (controller.message != null) {
      final text = controller.message!;
      controller.clearMessage();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(text)));
      });
    }
    if (controller.newestOffer != null &&
        controller.newestOffer != shownOffer) {
      shownOffer = controller.newestOffer;
      final offer = shownOffer!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            contentPadding: const EdgeInsets.all(14),
            content: OfferCard(offer: offer, prominent: true),
          ),
        );
      });
    }
  }
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.settings;
    final today = DateTime.now();
    final todayOffers = controller.offers
        .where((offer) => DateUtils.isSameDay(offer.detectedAt, today))
        .toList();
    final archivedCount = controller.offers.length - todayOffers.length;
    final acceptedToday = controller.offers.where(
      (offer) =>
          offer.acceptedAt != null &&
          DateUtils.isSameDay(offer.acceptedAt, today),
    );
    final revenue = acceptedToday.fold<double>(
      0,
      (total, offer) => total + offer.fare,
    );
    final kmToday = acceptedToday.fold<double>(
      0,
      (total, offer) => total + offer.totalKm,
    );
    final fuelCost = kmToday * s.selectedFuelCostPerKm;
    final balanceAfterFuel = revenue - fuelCost;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: 'Media minima',
                value: 'R\$ ${s.minimumFarePerKm.toStringAsFixed(2)}/km',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Metric(label: 'Combustivel', value: s.recommendedFuel),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resultado de hoje',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Aceitas: ${acceptedToday.length}  |  Receita: R\$ ${revenue.toStringAsFixed(2)}',
                ),
                Text(
                  'Km estimado: ${kmToday.toStringAsFixed(2)} km  |  ${s.recommendedFuel}: -R\$ ${fuelCost.toStringAsFixed(2)}',
                ),
                Text(
                  'Saldo apos combustivel: R\$ ${balanceAfterFuel.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: controller.toggleAndroidScreenMonitor,
          icon: Icon(
            controller.screenMonitorRunning
                ? Icons.stop_circle_outlined
                : Icons.screen_search_desktop_outlined,
          ),
          label: Text(
            controller.screenMonitorRunning
                ? 'Parar leitura da tela'
                : 'Iniciar leitura Uber / 99',
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                'Ofertas de hoje',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ArchivePage(controller: controller),
                ),
              ),
              icon: const Icon(Icons.archive_outlined),
              label: Text('Arquivo ($archivedCount)'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (todayOffers.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Nenhuma corrida analisada hoje.')),
            ),
          ),
        for (final offer in todayOffers) OfferCard(offer: offer),
      ],
    );
  }
}

class ArchivePage extends StatelessWidget {
  const ArchivePage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Corridas arquivadas')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final today = DateTime.now();
        final archived = controller.offers
            .where((offer) => !DateUtils.isSameDay(offer.detectedAt, today))
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Dados mantidos por ate 15 dias no aparelho.'),
            const SizedBox(height: 10),
            if (archived.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Nenhuma corrida arquivada.')),
                ),
              ),
            for (final offer in archived) OfferCard(offer: offer),
          ],
        );
      },
    ),
  );
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final days = _weeklyDays(controller);
    final totalRevenue = days.fold<double>(
      0,
      (total, day) => total + day.revenue,
    );
    final totalFuel = days.fold<double>(
      0,
      (total, day) => total + day.fuelCost,
    );
    final totalKm = days.fold<double>(0, (total, day) => total + day.km);
    final totalBalance = totalRevenue - totalFuel;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Text('Ganhos da semana', style: Theme.of(context).textTheme.titleLarge),
        const Text('Ultimos 7 dias, considerando corridas aceitas.'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: 'Receita',
                value: 'R\$ ${totalRevenue.toStringAsFixed(2)}',
              ),
            ),
            Expanded(
              child: _Metric(
                label: 'Combustivel',
                value: '-R\$ ${totalFuel.toStringAsFixed(2)}',
              ),
            ),
            Expanded(
              child: _Metric(
                label: 'Saldo',
                value: 'R\$ ${totalBalance.toStringAsFixed(2)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text('Km estimado pelas aceitas: ${totalKm.toStringAsFixed(2)} km'),
        const SizedBox(height: 22),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
            child: WeeklyBarChart(days: days),
          ),
        ),
        const SizedBox(height: 8),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Legend(color: Color(0xFF32A06A), label: 'Receita'),
            SizedBox(width: 18),
            _Legend(color: Color(0xFFDB545C), label: 'Combustivel'),
          ],
        ),
      ],
    );
  }

  List<DayEarnings> _weeklyDays(AppController controller) {
    final now = DateTime.now();
    return List.generate(7, (index) {
      final date = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 6 - index));
      final accepted = controller.offers.where(
        (offer) =>
            offer.acceptedAt != null &&
            DateUtils.isSameDay(offer.acceptedAt, date),
      );
      final revenue = accepted.fold<double>(
        0,
        (total, offer) => total + offer.fare,
      );
      final km = accepted.fold<double>(
        0,
        (total, offer) => total + offer.totalKm,
      );
      return DayEarnings(
        date: date,
        revenue: revenue,
        km: km,
        fuelCost: km * controller.settings.selectedFuelCostPerKm,
      );
    });
  }
}

class DayEarnings {
  const DayEarnings({
    required this.date,
    required this.revenue,
    required this.km,
    required this.fuelCost,
  });

  final DateTime date;
  final double revenue;
  final double km;
  final double fuelCost;
}

class WeeklyBarChart extends StatelessWidget {
  const WeeklyBarChart({super.key, required this.days});

  final List<DayEarnings> days;

  @override
  Widget build(BuildContext context) {
    const weekdays = ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'];
    final maximum = days.fold<double>(
      1,
      (value, day) => value > day.revenue && value > day.fuelCost
          ? value
          : (day.revenue > day.fuelCost ? day.revenue : day.fuelCost),
    );
    return SizedBox(
      height: 220,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _Bar(
                          height: 155 * (day.revenue / maximum),
                          color: const Color(0xFF32A06A),
                        ),
                        const SizedBox(width: 3),
                        _Bar(
                          height: 155 * (day.fuelCost / maximum),
                          color: const Color(0xFFDB545C),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    weekdays[day.date.weekday - 1],
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 15,
    height: height.clamp(2.0, 155.0).toDouble(),
    decoration: BoxDecoration(
      color: color,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(width: 12, height: 12, color: color),
      const SizedBox(width: 5),
      Text(label),
    ],
  );
}

class OfferCard extends StatelessWidget {
  const OfferCard({super.key, required this.offer, this.prominent = false});

  final RideOffer offer;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final color = offer.isWorthwhile ? Colors.green : Colors.red;
    final time = DateFormat('dd/MM HH:mm').format(offer.detectedAt);
    return Card(
      color: color.withValues(alpha: prominent ? .22 : .12),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color.withValues(alpha: .7)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  offer.platformLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                const Spacer(),
                if (offer.accepted)
                  Text(
                    offer.completed ? 'FINALIZADA' : 'ACEITA',
                    style: TextStyle(
                      color: Colors.blue.shade200,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  )
                else
                  Text(
                    offer.isWorthwhile
                        ? 'DENTRO DOS PARAMETROS'
                        : 'FORA DOS PARAMETROS',
                    style: TextStyle(
                      color: color.shade300,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'R\$ ${offer.fare.toStringAsFixed(2)}  |  '
              'R\$ ${offer.farePerKm.toStringAsFixed(2)}/km',
              style: TextStyle(
                color: color.shade200,
                fontWeight: FontWeight.w700,
                fontSize: prominent ? 21 : 17,
              ),
            ),
            Text(
              'Ate passageiro: ${offer.pickupKm.toStringAsFixed(1)} km   '
              'Destino: ${offer.destinationKm.toStringAsFixed(1)} km',
            ),
            if (!prominent)
              Text(time, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class ParametersPage extends StatefulWidget {
  const ParametersPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ParametersPage> createState() => _ParametersPageState();
}

class _ParametersPageState extends State<ParametersPage> {
  late final TextEditingController pickup;
  late final TextEditingController destination;
  late final TextEditingController farePerKm;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    pickup = _numberController(s.maxPickupKm);
    destination = _numberController(s.maxDestinationKm);
    farePerKm = _numberController(s.minimumFarePerKm);
  }

  @override
  void dispose() {
    pickup.dispose();
    destination.dispose();
    farePerKm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
    children: [
      Text(
        'Quando uma corrida vale a pena?',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'O card fica verde apenas quando cumprir as tres regras. '
        'A media minima e comparada diretamente ao valor R\$ / km do popup.',
      ),
      const SizedBox(height: 18),
      _field(pickup, 'Distancia maxima ate o passageiro (km)'),
      _field(destination, 'Distancia maxima ate o destino (km)'),
      _field(farePerKm, 'Media minima esperada por km (R\$)'),
      const SizedBox(height: 12),
      FilledButton(onPressed: _save, child: const Text('Salvar parametros')),
    ],
  );

  void _save() {
    final previous = widget.controller.settings;
    final maxPickup = _value(pickup);
    final maxDestination = _value(destination);
    final minimumFarePerKm = _value(farePerKm);
    if (maxPickup <= 0 || maxDestination <= 0 || minimumFarePerKm <= 0) {
      widget.controller.showMessage(
        'Informe distancias e media por km maiores que zero.',
      );
      return;
    }
    widget.controller.saveSettings(
      previous.copyWith(
        maxPickupKm: maxPickup,
        maxDestinationKm: maxDestination,
        minimumFarePerKm: minimumFarePerKm,
      ),
    );
  }
}

class VehicleCostPage extends StatefulWidget {
  const VehicleCostPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<VehicleCostPage> createState() => _VehicleCostPageState();
}

class _VehicleCostPageState extends State<VehicleCostPage> {
  late final TextEditingController gasolinePrice;
  late final TextEditingController ethanolPrice;
  late final TextEditingController gasolineConsumption;
  late final TextEditingController ethanolConsumption;
  late final TextEditingController otherCost;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    gasolinePrice = _numberController(s.gasolinePrice);
    ethanolPrice = _numberController(s.ethanolPrice);
    gasolineConsumption = _numberController(s.gasolineConsumption);
    ethanolConsumption = _numberController(s.ethanolConsumption);
    otherCost = _numberController(s.otherCostPerKm);
  }

  @override
  void dispose() {
    gasolinePrice.dispose();
    ethanolPrice.dispose();
    gasolineConsumption.dispose();
    ethanolConsumption.dispose();
    otherCost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
      children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Melhor abastecer com ${s.recommendedFuel}\n'
              'Custo operacional: R\$ ${s.operationCostPerKm.toStringAsFixed(2)}/km\n'
              'Seu limite definido: R\$ ${s.minimumFarePerKm.toStringAsFixed(2)}/km\n'
              'Custo calculado: R\$ ${s.operationCostPerKm.toStringAsFixed(2)}/km',
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _field(gasolinePrice, 'Preco da gasolina (R\$ / litro)'),
        _field(ethanolPrice, 'Preco do etanol (R\$ / litro)'),
        _field(gasolineConsumption, 'Rendimento gasolina (km / litro)'),
        _field(ethanolConsumption, 'Rendimento etanol (km / litro)'),
        _field(otherCost, 'Manutencao/depreciacao por km (R\$)'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _save,
          child: const Text('Atualizar recomendacao'),
        ),
      ],
    );
  }

  void _save() {
    final previous = widget.controller.settings;
    final gasPrice = _value(gasolinePrice);
    final alcoholPrice = _value(ethanolPrice);
    final gasKmL = _value(gasolineConsumption);
    final alcoholKmL = _value(ethanolConsumption);
    final extra = _value(otherCost);
    if (gasPrice <= 0 ||
        alcoholPrice <= 0 ||
        gasKmL <= 0 ||
        alcoholKmL <= 0 ||
        extra < 0) {
      widget.controller.showMessage(
        'Precos e rendimentos devem ser maiores que zero.',
      );
      return;
    }
    widget.controller.saveSettings(
      previous.copyWith(
        gasolinePrice: gasPrice,
        ethanolPrice: alcoholPrice,
        gasolineConsumption: gasKmL,
        ethanolConsumption: alcoholKmL,
        otherCostPerKm: extra,
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    ),
  );
}

TextEditingController _numberController(double value) =>
    TextEditingController(text: value.toStringAsFixed(2).replaceAll('.', ','));

double _value(TextEditingController controller) =>
    double.tryParse(controller.text.replaceAll(',', '.')) ?? 0;

Widget _field(TextEditingController controller, String label) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  ),
);
