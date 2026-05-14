import os
import glob
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from dash import Dash, dcc, html, Input, Output, State, callback_context
import dash_bootstrap_components as dbc

# Flask 앱과 연동하기 위한 설정
# app.py에서 이 모듈을 임포트하여 Flask 서버에 Dash 앱을 마운트할 예정

RESULTS_DIR = os.environ.get("ROCHE_NXT_DIR", "/roche_nxt") + "/results"

def create_dash_app(flask_app):
    dash_app = Dash(
        __name__, 
        server=flask_app, 
        url_base_pathname='/interactive/',
        external_stylesheets=[dbc.themes.BOOTSTRAP]
    )

    dash_app.layout = dbc.Container([
        dbc.Row([
            dbc.Col([
                html.H2("RNAseq Interactive Analysis", className="text-primary mt-4 mb-4"),
            ], width=12)
        ]),
        dbc.Row([
            dbc.Col([
                html.Label("Select Sample:", className="fw-bold"),
                dcc.Dropdown(
                    id='sample-dropdown',
                    options=[],
                    value=None,
                    clearable=False,
                    className="mb-3"
                ),
            ], width=4),
            dbc.Col([
                html.Label("Search Gene (Symbol or ID):", className="fw-bold"),
                dcc.Input(
                    id='gene-search-input',
                    type='text',
                    placeholder='e.g., TP53 or ENSG00000141510',
                    className="form-control mb-3",
                    debounce=True
                ),
            ], width=4),
            dbc.Col([
                html.Label("Highlight Gene on Plot:", className="fw-bold"),
                html.Div(id='selected-gene-display', className="p-2 bg-light border rounded text-success fw-bold", style={'height': '38px'})
            ], width=4)
        ]),
        dbc.Row([
            dbc.Col([
                dcc.Tabs(id="tabs", value='tab-ma', children=[
                    dcc.Tab(label='MA Plot (log2 TPM vs log2 CPM)', value='tab-ma'),
                    dcc.Tab(label='Volcano Plot (Mock - needs DESeq2)', value='tab-volcano'),
                    dcc.Tab(label='Count Distribution', value='tab-dist'),
                ]),
                html.Div(id='tabs-content', className="mt-4")
            ], width=12)
        ]),
        # Hidden div to store data
        dcc.Store(id='store-data')
    ], fluid=True)

    from flask import request

    @dash_app.callback(
        Output('sample-dropdown', 'options'),
        Output('sample-dropdown', 'value'),
        Output('gene-search-input', 'value'),
        Input('sample-dropdown', 'id') # Dummy input to trigger on load
    )
    def update_sample_dropdown(_):
        # Find all expression summary files
        pattern = os.path.join(RESULTS_DIR, "*", "expression_plots", "*_expression_summary.tsv")
        files = glob.glob(pattern)
        
        options = []
        for f in files:
            # Extract sample name from path: RESULTS_DIR/<sample_name>/expression_plots/...
            parts = f.split('/')
            if len(parts) >= 3:
                sample_name = parts[-3]
                options.append({'label': sample_name, 'value': sample_name})
        
        # Sort options
        options = sorted(options, key=lambda x: x['label'])
        
        # Check if sample and gene are provided in URL query string
        url_sample = request.args.get('sample')
        url_gene = request.args.get('gene', '')
        
        value = None
        if url_sample and any(opt['value'] == url_sample for opt in options):
            value = url_sample
        elif options:
            value = options[0]['value']
            
        return options, value, url_gene

    @dash_app.callback(
        Output('store-data', 'data'),
        Input('sample-dropdown', 'value')
    )
    def load_data(sample_name):
        if not sample_name:
            return None
            
        file_path = os.path.join(RESULTS_DIR, sample_name, "expression_plots", f"{sample_name}_expression_summary.tsv")
        if not os.path.isfile(file_path):
            return None
            
        try:
            df = pd.read_csv(file_path, sep="\\t")
            # Calculate log2 values if not present
            if 'log2CPM' not in df.columns:
                df['log2CPM'] = np.log2(df['CPM'] + 1)
            if 'log2TPM' not in df.columns:
                df['log2TPM'] = np.log2(df['TPM'] + 1)
                
            # Create a combined label for hover
            df['label'] = df.apply(
                lambda row: row['gene_symbol'] if pd.notna(row['gene_symbol']) and row['gene_symbol'] != row['gene_id'] else row['gene_id'], 
                axis=1
            )
            
            return df.to_dict('records')
        except Exception as e:
            print(f"Error loading data: {e}")
            return None

    @dash_app.callback(
        Output('selected-gene-display', 'children'),
        Input('gene-search-input', 'value'),
        State('store-data', 'data')
    )
    def update_selected_gene(search_term, data):
        if not search_term or not data:
            return "None"
            
        search_term = search_term.strip().upper()
        df = pd.DataFrame(data)
        
        # Search by symbol or ID
        match = df[(df['gene_symbol'].str.upper() == search_term) | (df['gene_id'].str.upper() == search_term)]
        
        if not match.empty:
            gene = match.iloc[0]
            return f"{gene['gene_symbol']} ({gene['gene_id']}) - TPM: {gene['TPM']:.2f}"
        else:
            return "Not found"

    @dash_app.callback(
        Output('tabs-content', 'children'),
        Input('tabs', 'value'),
        Input('store-data', 'data'),
        Input('gene-search-input', 'value'),
        State('sample-dropdown', 'value')
    )
    def render_content(tab, data, search_term, sample_name):
        if not data:
            return html.Div("No data available for selected sample.", className="text-danger")
            
        df = pd.DataFrame(data)
        df_expr = df[df['count'] > 0].copy()
        
        search_term = search_term.strip().upper() if search_term else ""
        
        if tab == 'tab-ma':
            fig = px.scatter(
                df_expr, x="log2CPM", y="log2TPM", 
                hover_name="label", 
                hover_data={"gene_id": True, "count": True, "TPM": True, "log2CPM": False, "log2TPM": False},
                labels={"log2CPM": "log2(CPM + 1)", "log2TPM": "log2(TPM + 1)"},
                opacity=0.5, 
                color_discrete_sequence=["#7030A0"]
            )
            
            # Highlight searched gene
            if search_term:
                match = df_expr[(df_expr['gene_symbol'].str.upper() == search_term) | (df_expr['gene_id'].str.upper() == search_term)]
                if not match.empty:
                    fig.add_trace(go.Scatter(
                        x=match['log2CPM'], y=match['log2TPM'],
                        mode='markers+text',
                        marker=dict(color='red', size=12, symbol='star'),
                        text=match['label'],
                        textposition="top center",
                        name="Searched Gene",
                        hoverinfo="text",
                        hovertext=match['label'] + "<br>TPM: " + match['TPM'].round(2).astype(str)
                    ))
            
            fig.update_layout(
                title=f"Expression MA-like Plot - {sample_name}",
                height=600,
                template="plotly_white",
                clickmode='event+select'
            )
            
            return dcc.Graph(id='ma-plot', figure=fig)
            
        elif tab == 'tab-volcano':
            # This is a mock volcano plot since we don't have DESeq2 output yet
            # We'll just plot log2TPM vs log2CPM as a placeholder, but color it like a volcano
            
            # Create mock log2FoldChange and p-value for demonstration
            import numpy as np
            np.random.seed(42)
            df_expr['mock_lfc'] = np.random.normal(0, 2, size=len(df_expr))
            df_expr['mock_pval'] = np.random.uniform(0, 1, size=len(df_expr))
            df_expr['mock_padj'] = df_expr['mock_pval'] * 1.5 # rough FDR
            df_expr['mock_padj'] = df_expr['mock_padj'].clip(upper=1.0)
            df_expr['mock_log10pval'] = -np.log10(df_expr['mock_padj'] + 1e-10)
            
            # Color by significance
            conditions = [
                (df_expr['mock_padj'] < 0.05) & (df_expr['mock_lfc'] > 1),
                (df_expr['mock_padj'] < 0.05) & (df_expr['mock_lfc'] < -1)
            ]
            choices = ['Up-regulated', 'Down-regulated']
            df_expr['status'] = np.select(conditions, choices, default='Not Significant')
            
            color_map = {'Up-regulated': '#C00000', 'Down-regulated': '#4472C4', 'Not Significant': '#D9D9D9'}
            
            fig = px.scatter(
                df_expr, x="mock_lfc", y="mock_log10pval", 
                color="status", color_discrete_map=color_map,
                hover_name="label", 
                hover_data={"gene_id": True, "TPM": True, "status": False},
                labels={"mock_lfc": "log2 Fold Change", "mock_log10pval": "-log10(p-adj)"},
                opacity=0.7
            )
            
            fig.add_vline(x=1, line_dash="dash", line_color="gray")
            fig.add_vline(x=-1, line_dash="dash", line_color="gray")
            fig.add_hline(y=-np.log10(0.05), line_dash="dash", line_color="gray")
            
            # Highlight searched gene
            if search_term:
                match = df_expr[(df_expr['gene_symbol'].str.upper() == search_term) | (df_expr['gene_id'].str.upper() == search_term)]
                if not match.empty:
                    fig.add_trace(go.Scatter(
                        x=match['mock_lfc'], y=match['mock_log10pval'],
                        mode='markers+text',
                        marker=dict(color='black', size=12, symbol='star', line=dict(color='yellow', width=2)),
                        text=match['label'],
                        textposition="top center",
                        name="Searched Gene"
                    ))
            
            fig.update_layout(
                title=f"Mock Volcano Plot (Requires DESeq2) - {sample_name}",
                height=600,
                template="plotly_white"
            )
            
            return html.Div([
                dbc.Alert("Note: This is a mock volcano plot. Real differential expression requires multiple samples and DESeq2 analysis.", color="warning"),
                dcc.Graph(id='volcano-plot', figure=fig)
            ])
            
        elif tab == 'tab-dist':
            fig = px.histogram(
                df_expr, x="log2CPM", nbins=100,
                title=f"Read Count Distribution - {sample_name}",
                labels={"log2CPM": "log2(CPM + 1)"},
                color_discrete_sequence=["#4472C4"]
            )
            
            # Highlight searched gene
            if search_term:
                match = df_expr[(df_expr['gene_symbol'].str.upper() == search_term) | (df_expr['gene_id'].str.upper() == search_term)]
                if not match.empty:
                    val = match.iloc[0]['log2CPM']
                    fig.add_vline(x=val, line_dash="solid", line_color="red", line_width=2, 
                                 annotation_text=f"{match.iloc[0]['label']}", annotation_position="top right")
            
            fig.update_layout(
                height=600,
                template="plotly_white"
            )
            
            return dcc.Graph(id='dist-plot', figure=fig)

    return dash_app
