import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/models/menu_item.dart';
import '../../../shared/models/restaurant.dart';

class MenuState {
  final Restaurant? restaurant;
  final List<MenuCategory> categories;
  final bool isLoading;
  final String? error;

  const MenuState({
    this.restaurant,
    this.categories = const [],
    this.isLoading = false,
    this.error,
  });
}

class MenuNotifier extends StateNotifier<MenuState> {
  final ApiClient _api;

  MenuNotifier(this._api) : super(const MenuState());

  Future<void> loadMenu(String restaurantSlug, String tableNumber) async {
    state = const MenuState(isLoading: true);
    try {
      final responses = await Future.wait([
        _api.get('/api/menu', queryParameters: {
          'restaurant': restaurantSlug,
          'table': tableNumber,
        }),
        _api.get('/api/restaurants/$restaurantSlug'),
      ]);
      final categoriesData = responses[0].data as List<dynamic>;
      final categories = categoriesData
          .map((c) => MenuCategory.fromJson(c as Map<String, dynamic>))
          .toList();
      final restaurant = Restaurant.fromJson(responses[1].data as Map<String, dynamic>);
      state = MenuState(restaurant: restaurant, categories: categories);
    } on DioException catch (e) {
      state = MenuState(error: ApiException.fromDioError(e).message);
    } catch (e) {
      state = MenuState(error: e.toString());
    }
  }
}

final menuProvider = StateNotifierProvider.family<MenuNotifier, MenuState, (String, String)>(
  (ref, params) => MenuNotifier(ref.read(apiClientProvider)),
);
