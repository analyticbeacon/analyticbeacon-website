#!/usr/bin/env python3
"""
ANALYTIC BEACON — Monitor de Noticias con Verificación Cruzada
Corre en la nube de GitHub cada 4 horas — independiente de OpenClaw y PC local
"""

import feedparser, requests, json, os, re
from datetime import datetime, timezone
from collections import defaultdict

# ── CONFIGURACIÓN ──
ANT_KEY = os.environ.get('ANTHROPIC_API_KEY', '')
BOT_TOKEN = os.environ.get('TELEGRAM_BOT_TOKEN', '')
CHAT_ID = os.environ.get('TELEGRAM_CHAT_ID', '')

# ── FUENTES RSS — MÚLTIPLES PARA VERIFICACIÓN CRUZADA ──
FUENTES = {
    'reuters':    'https://feeds.reuters.com/reuters/topNews',
    'bbc':        'https://feeds.bbci.co.uk/news/world/rss.xml',
    'ap':         'https://feeds.apnews.com/rss/apf-topnews',
    'aljazeera':  'https://www.aljazeera.com/xml/rss/all.xml',
    'bloomberg':  'https://feeds.bloomberg.com/markets/news.rss',
}

# ── KEYWORDS DE ALTA IMPORTANCIA ──
KEYWORDS_ALERTA = [
    'war declared', 'nuclear', 'invasion', 'coup', 'sanctions',
    'market crash', 'interest rate', 'default', 'assassination',
    'ceasefire', 'peace deal', 'trade war', 'tariff', 'crisis',
    'embargo', 'collapse', 'explosion', 'attack', 'summit'
]

def fetch_feed(nombre, url):
    """Obtiene titulares de un feed RSS"""
    try:
        feed = feedparser.parse(url)
        titulares = []
        for entry in feed.entries[:10]:
            titulo = entry.get('title', '').strip()
            resumen = entry.get('summary', '')[:200]
            if titulo:
                titulares.append({
                    'titulo': titulo,
                    'resumen': resumen,
                    'fuente': nombre,
                    'link': entry.get('link', '')
                })
        print(f"  ✅ {nombre}: {len(titulares)} titulares")
        return titulares
    except Exception as e:
        print(f"  ❌ {nombre}: {e}")
        return []

def encontrar_eventos_coincidentes(todos_titulares):
    """
    VERIFICACIÓN CRUZADA:
    Un evento se considera verificado si aparece en ≥2 fuentes independientes
    """
    eventos_por_tema = defaultdict(list)

    for item in todos_titulares:
        titulo_lower = item['titulo'].lower()
        for keyword in KEYWORDS_ALERTA:
            if keyword in titulo_lower:
                eventos_por_tema[keyword].append(item)

    # Solo eventos confirmados por 2+ fuentes
    eventos_verificados = {}
    for keyword, items in eventos_por_tema.items():
        fuentes_unicas = set(i['fuente'] for i in items)
        if len(fuentes_unicas) >= 2:
            eventos_verificados[keyword] = {
                'items': items,
                'fuentes': list(fuentes_unicas),
                'confirmado': True,
                'nivel': 'ALTO' if len(fuentes_unicas) >= 3 else 'MEDIO'
            }
            print(f"  🔴 VERIFICADO: '{keyword}' en {fuentes_unicas}")

    return eventos_verificados

def generar_articulo_verificado(evento_data, keyword):
    """Genera artículo solo si el evento está verificado por múltiples fuentes"""
    if not ANT_KEY:
        return None

    titulares = [f"- [{i['fuente'].upper()}] {i['titulo']}" for i in evento_data['items'][:6]]
    titulares_texto = '\n'.join(titulares)
    fuentes = ', '.join(evento_data['fuentes'])

    prompt = f"""Eres el analista jefe de Analytic Beacon, una publicación de inteligencia geopolítica y económica de alto nivel.

EVENTO VERIFICADO por múltiples fuentes ({fuentes}):
{titulares_texto}

Redacta un artículo de análisis de 300-400 palabras con esta estructura:
1. TITULAR: Conciso, informativo, sin sensacionalismo
2. CONTEXTO: Qué pasó y por qué importa (2 párrafos)
3. ANÁLISIS: Implicaciones geopolíticas/económicas (2 párrafos)
4. PROYECCIÓN: Qué esperar en las próximas 48-72 horas (1 párrafo)
5. ETIQUETAS: 5 tags relevantes

IMPORTANTE: Solo incluye hechos confirmados. No especules sin base. Menciona las fuentes verificadoras.
Tono: profesional, directo, sin alarmismo innecesario."""

    try:
        response = requests.post(
            'https://api.anthropic.com/v1/messages',
            headers={
                'x-api-key': ANT_KEY,
                'anthropic-version': '2023-06-01',
                'content-type': 'application/json'
            },
            json={
                'model': 'claude-haiku-4-5',
                'max_tokens': 800,
                'messages': [{'role': 'user', 'content': prompt}]
            },
            timeout=30
        )
        data = response.json()
        texto = data['content'][0]['text']

        # Calcular costo
        input_tokens = data['usage']['input_tokens']
        output_tokens = data['usage']['output_tokens']
        costo = (input_tokens * 0.00025 + output_tokens * 0.00125) / 1000
        print(f"  💰 Costo: ${costo:.4f} | Tokens: {input_tokens}+{output_tokens}")

        return {'texto': texto, 'costo': costo, 'tokens': input_tokens + output_tokens}
    except Exception as e:
        print(f"  ❌ Error Claude: {e}")
        return None

def notificar_telegram(evento, articulo, keyword):
    """Envía notificación a Telegram para aprobación humana"""
    if not BOT_TOKEN or not CHAT_ID:
        return

    fuentes = ', '.join(evento['fuentes'])
    nivel = evento['nivel']
    emoji = '🔴' if nivel == 'ALTO' else '🟡'

    msg = f"""{emoji} *NOTICIA VERIFICADA — ANALYTIC BEACON*
📌 Tema: `{keyword.upper()}`
✅ Fuentes confirmadas: {fuentes}
💰 Costo generación: ${articulo['costo']:.4f}

*VISTA PREVIA:*
{articulo['texto'][:800]}...

_¿Publicar en analyticbeacon.com?_
Responde: *SI* para publicar | *NO* para descartar"""

    requests.post(
        f'https://api.telegram.org/bot{BOT_TOKEN}/sendMessage',
        json={'chat_id': CHAT_ID, 'text': msg, 'parse_mode': 'Markdown'},
        timeout=10
    )
    print(f"  📱 Notificación Telegram enviada")

def actualizar_log_costos(articulo, keyword):
    """Registra costo en log JSON para contabilidad"""
    log_file = 'cost_log.json'
    log = []
    if os.path.exists(log_file):
        with open(log_file) as f:
            log = json.load(f)

    log.append({
        'fecha': datetime.now(timezone.utc).isoformat(),
        'evento': keyword,
        'tokens': articulo['tokens'],
        'costo_usd': articulo['costo'],
        'modelo': 'claude-haiku-4-5'
    })

    with open(log_file, 'w') as f:
        json.dump(log, f, indent=2)

    total_mes = sum(e['costo_usd'] for e in log
                   if e['fecha'][:7] == datetime.now().strftime('%Y-%m'))
    print(f"  📊 Gasto acumulado este mes: ${total_mes:.4f}")

# ── EJECUCIÓN PRINCIPAL ──
def main():
    print(f"\n{'='*50}")
    print(f"ANALYTIC BEACON — Monitor {datetime.now().strftime('%Y-%m-%d %H:%M')} UTC")
    print(f"{'='*50}\n")

    # 1. Recopilar feeds
    todos_titulares = []
    for nombre, url in FUENTES.items():
        titulares = fetch_feed(nombre, url)
        todos_titulares.extend(titulares)

    print(f"\nTotal titulares recopilados: {len(todos_titulares)}")

    # 2. Verificación cruzada
    print("\n📡 Verificando eventos en múltiples fuentes...")
    eventos_verificados = encontrar_eventos_coincidentes(todos_titulares)

    if not eventos_verificados:
        print("\n✅ Sin eventos críticos verificados en múltiples fuentes.")
        print("   (Esto es bueno — significa que no publicamos sin verificar)")
        return

    print(f"\n🔴 {len(eventos_verificados)} evento(s) verificado(s) encontrado(s)")

    # 3. Generar artículos solo para eventos verificados
    for keyword, evento in list(eventos_verificados.items())[:2]:  # Max 2 por corrida
        print(f"\n✍️ Generando artículo para: {keyword}")
        articulo = generar_articulo_verificado(evento, keyword)

        if articulo:
            # 4. Registrar costo
            actualizar_log_costos(articulo, keyword)

            # 5. Notificar para aprobación humana
            notificar_telegram(evento, articulo, keyword)

    print(f"\n{'='*50}")
    print("Monitor completado. Esperando aprobación humana vía Telegram.")

if __name__ == '__main__':
    main()
