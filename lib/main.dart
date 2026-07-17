import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'products.dart';

void main() => runApp(const MaqadiApp());

class GroceryItem {
  GroceryItem({required this.name, required this.category, this.done = false, this.qty = 1});
  String name; String category; bool done; int qty;
  Map<String, dynamic> toJson() => {'name': name, 'category': category, 'done': done, 'qty': qty};
  factory GroceryItem.fromJson(Map<String, dynamic> j) => GroceryItem(name: j['name'], category: j['category'], done: j['done'] ?? false, qty: j['qty'] ?? 1);
}

class MaqadiApp extends StatefulWidget { const MaqadiApp({super.key}); @override State<MaqadiApp> createState() => _MaqadiAppState(); }
class _MaqadiAppState extends State<MaqadiApp> {
  ThemeMode mode = ThemeMode.system;
  @override Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false, title: 'مقاضي', themeMode: mode,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF2E7D32), scaffoldBackgroundColor: const Color(0xFFF7F8F6)),
    darkTheme: ThemeData.dark(useMaterial3: true).copyWith(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF66BB6A), brightness: Brightness.dark)),
    home: Directionality(textDirection: TextDirection.rtl, child: HomePage(onToggleTheme: () => setState(() => mode = mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark))),
  );
}

class HomePage extends StatefulWidget { const HomePage({super.key, required this.onToggleTheme}); final VoidCallback onToggleTheme; @override State<HomePage> createState() => _HomePageState(); }
class _HomePageState extends State<HomePage> {
  final controller = TextEditingController();
  final List<GroceryItem> items = [];
  final Set<String> favorites = {};
  final Map<String, int> frequency = {};
  String query = '', selectedCategory = 'الكل';
  bool hideDone = false, favoritesOnly = false;
  static const itemsKey='maqadi_items_v24', favKey='maqadi_favorites_v24', freqKey='maqadi_frequency_v24';

  List<String> get categories => ['الكل', ...{for (final p in products) p.category}];
  @override void initState() { super.initState(); _load(); controller.addListener(() => setState(() => query = controller.text.trim())); }
  @override void dispose() { controller.dispose(); super.dispose(); }

  Future<void> _load() async {
    final p=await SharedPreferences.getInstance();
    final raw=p.getString(itemsKey), rawFreq=p.getString(freqKey);
    if (!mounted) return;
    setState(() {
      if(raw!=null) items.addAll((jsonDecode(raw) as List).map((e)=>GroceryItem.fromJson(Map<String,dynamic>.from(e))));
      favorites.addAll(p.getStringList(favKey)??const []);
      if(rawFreq!=null) frequency.addAll(Map<String,dynamic>.from(jsonDecode(rawFreq)).map((k,v)=>MapEntry(k,v as int)));
    });
  }
  Future<void> _save() async { final p=await SharedPreferences.getInstance(); await p.setString(itemsKey,jsonEncode(items.map((e)=>e.toJson()).toList())); await p.setStringList(favKey,favorites.toList()); await p.setString(freqKey,jsonEncode(frequency)); }
  String _n(String s)=>s.toLowerCase().replaceAll(RegExp('[أإآ]'),'ا').replaceAll('ة','ه').replaceAll('ى','ي').trim();
  Product? _exact(String name) { final n=_n(name); for(final p in products){if(_n(p.name)==n||p.aliases.any((a)=>_n(a)==n)) return p;} return null; }
  String _category(String name) { final x=_exact(name); if(x!=null)return x.category; final n=_n(name); for(final p in products){if(n.contains(_n(p.name))||p.aliases.any((a)=>n.contains(_n(a))))return p.category;} return 'أخرى'; }
  void _add(String raw,[String? cat]) {
    var changed=false;
    for(final v in raw.split(RegExp(r'[\n,،]+')).map((e)=>e.trim()).where((e)=>e.isNotEmpty)){
      GroceryItem? existing; for(final i in items){if(_n(i.name)==_n(v)){existing=i;break;}}
      if(existing!=null){existing.qty++;changed=true;continue;}
      final canonical=_exact(v)?.name??v; items.add(GroceryItem(name:canonical,category:cat??_category(v))); frequency[canonical]=(frequency[canonical]??0)+1; changed=true;
    }
    if(changed){controller.clear();setState((){});_save();}
  }
  List<Product> get suggestions {
    final q=_n(query);
    final list=products.where((p)=>(selectedCategory=='الكل'||p.category==selectedCategory)&&(!favoritesOnly||favorites.contains(p.name))&&(q.isEmpty||_n(p.name).contains(q)||p.aliases.any((a)=>_n(a).contains(q)))).toList();
    list.sort((a,b){final af=favorites.contains(a.name)?1:0,bf=favorites.contains(b.name)?1:0;if(af!=bf)return bf.compareTo(af);final ac=frequency[a.name]??0,bc=frequency[b.name]??0;if(ac!=bc)return bc.compareTo(ac);return a.name.compareTo(b.name);});
    return list.take(query.isEmpty?24:12).toList();
  }

  @override Widget build(BuildContext context) {
    final done=items.where((e)=>e.done).length,total=items.length;
    final grouped=<String,List<GroceryItem>>{}; for(final i in items){if(hideDone&&i.done)continue;grouped.putIfAbsent(i.category,()=>[]).add(i);}
    return Scaffold(
      appBar:AppBar(title:const Text('مقاضي',style:TextStyle(fontWeight:FontWeight.w900)),actions:[IconButton(onPressed:widget.onToggleTheme,icon:const Icon(Icons.dark_mode_outlined))]),
      floatingActionButton:FloatingActionButton.extended(onPressed:()=>_add(controller.text),icon:const Icon(Icons.add),label:const Text('إضافة')),
      body:SafeArea(child:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[
        Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[const Text('قائمة هذا الأسبوع',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900)),const SizedBox(height:10),LinearProgressIndicator(value:total==0?0:done/total,minHeight:10,borderRadius:BorderRadius.circular(20)),const SizedBox(height:8),Text('تم شراء $done من $total • المتبقي ${total-done}')]))),
        const SizedBox(height:12),
        TextField(controller:controller,minLines:1,maxLines:4,onSubmitted:_add,decoration:InputDecoration(labelText:'ابحث أو أضف غرضًا',hintText:'مثال: حليب، بيض، خبز',prefixIcon:const Icon(Icons.search),suffixIcon:query.isEmpty?const Icon(Icons.add_circle):IconButton(onPressed:controller.clear,icon:const Icon(Icons.close)),border:OutlineInputBorder(borderRadius:BorderRadius.circular(18)))),
        const SizedBox(height:10),
        SizedBox(height:42,child:ListView.separated(scrollDirection:Axis.horizontal,itemCount:categories.length,separatorBuilder:(_,__)=>const SizedBox(width:8),itemBuilder:(_,i){final c=categories[i];return FilterChip(label:Text(c),selected:selectedCategory==c,onSelected:(_)=>setState(()=>selectedCategory=c));})),
        const SizedBox(height:8),
        Wrap(spacing:8,children:[FilterChip(avatar:const Icon(Icons.star,size:18),label:const Text('المفضلة'),selected:favoritesOnly,onSelected:(v)=>setState(()=>favoritesOnly=v)),FilterChip(avatar:const Icon(Icons.visibility_off,size:18),label:const Text('إخفاء المشتريات'),selected:hideDone,onSelected:(v)=>setState(()=>hideDone=v))]),
        const SizedBox(height:12),
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('اقتراحات ذكية',style:TextStyle(fontWeight:FontWeight.w800,fontSize:18)),Text('${products.length} منتج')]),
        const SizedBox(height:8),
        if(query.isNotEmpty&&_exact(query)==null) ListTile(tileColor:Theme.of(context).colorScheme.secondaryContainer,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),leading:const Icon(Icons.add),title:Text('إضافة "$query"'),subtitle:Text('التصنيف المتوقع: ${_category(query)}'),onTap:()=>_add(query)),
        Wrap(spacing:8,runSpacing:8,children:suggestions.map((p)=>InputChip(label:Text(p.name),onPressed:()=>_add(p.name,p.category),deleteIcon:Icon(favorites.contains(p.name)?Icons.star:Icons.star_border,size:18),onDeleted:(){setState((){favorites.contains(p.name)?favorites.remove(p.name):favorites.add(p.name);});_save();})).toList()),
        const SizedBox(height:14),
        if(items.isEmpty) const Padding(padding:EdgeInsets.only(top:30),child:Column(children:[Icon(Icons.shopping_cart_outlined,size:64),SizedBox(height:10),Text('قائمتك فارغة',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),Text('ابحث عن منتج أو أضف أول غرض')])),
        for(final e in grouped.entries)...[
          Padding(padding:const EdgeInsets.only(top:18,bottom:6),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(e.key,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),Text('${e.value.where((x)=>x.done).length}/${e.value.length}')])),
          ...e.value.map((item)=>Card(child:ListTile(leading:Checkbox(value:item.done,onChanged:(v){setState(()=>item.done=v??false);_save();}),title:Text(item.name,style:TextStyle(fontWeight:FontWeight.w700,decoration:item.done?TextDecoration.lineThrough:null)),subtitle:Text('الكمية: ${item.qty}'),trailing:PopupMenuButton<String>(onSelected:(v){if(v=='plus')item.qty++;if(v=='minus'&&item.qty>1)item.qty--;if(v=='fav'){favorites.contains(item.name)?favorites.remove(item.name):favorites.add(item.name);}if(v=='delete')items.remove(item);setState((){});_save();},itemBuilder:(_)=>[const PopupMenuItem(value:'plus',child:Text('زيادة الكمية')),const PopupMenuItem(value:'minus',child:Text('تقليل الكمية')),PopupMenuItem(value:'fav',child:Text(favorites.contains(item.name)?'إزالة من المفضلة':'إضافة للمفضلة')),const PopupMenuItem(value:'delete',child:Text('حذف'))]))))
        ]
      ]))
    );
  }
}
