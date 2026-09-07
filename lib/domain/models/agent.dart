// lib/models/agent.dart

class Agent {
  final String id;
  final String name;
  final String? description;
  final List<String>? capabilities;
  final bool? routable;
  final String? transport;

  const Agent({
    required this.id,
    required this.name,
    this.description,
    this.capabilities,
    this.routable,
    this.transport,
  });

  // ============================================================
  // ПРЕОБРАЗОВАНИЕ В JSON
  // ============================================================

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      if (capabilities != null) 'capabilities': capabilities,
      if (routable != null) 'routable': routable,
      if (transport != null) 'transport': transport,
    };
  }

  bool hasCapability(String capability) {
    return capabilities?.contains(capability) ?? false;
  }
}
