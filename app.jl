#=
This app implements a web UI for the package AIHelpMe.jl. This package lets you index the documentation from loaded Julia packages and ask questions about it using GPT
=#
using GenieFramework, AIHelpMe, Pkg, JLD2, Dates
using AIHelpMe: build_index, load_index!
using AIHelpMe.PT.Experimental.RAGTools: airag, setpropertynested
using StippleMarkdown

# load the markdown component to render text
@genietools
# this contains the list of installed packages
_packages = Pkg.installed() |> keys |> collect
# configuration for the RAG model
_kwargs = AIHelpMe.PT.Experimental.RAGTools.setpropertynested(AIHelpMe.RAG_KWARGS[],[:embedder_kwargs],:api_key,ENV["OPENAI_API_KEY"])
# initial index
index = AIHelpMe.MAIN_INDEX[]

#reactive code
@app begin
    # First, define reactive variables to hold the state of the UI components
    # configuration
    @in openai_key = ENV["OPENAI_API_KEY"]
    @in model = "gpt4"
    @out model_options = ["gpt4", "gpt3"]
    @out packages = _packages
    @in index_in_use = "AIHelpMe"
    @in build_index = false
    @private kwargs = _kwargs
    # chat
    @out history = [("Welcome!","I'm here to help you with your Julia code.")]
    @in question = ""
    @out answer = "answer text here"
    @out cost = 0.0
    @out tokens = 0.0
    @out total_cost::Float16 = 0.0
    @out total_tokens = 0.0
    @in submit = false
    @in reset_chat = false
    # Second, define reactive handlers to execute code when a reactive variable changes
    # When the submit button is clicked, send the question the GPT API and update the metrics
    @onbutton submit begin
        index=load("indexes/$index_in_use.jld2")["idx"];
        response = AIHelpMe.PT.Experimental.RAGTools.airag(AIHelpMe.RAG_CONFIG[], index; question, kwargs...)
        answer = response.content
        cost, tokens = round(response.cost,digits=3), response.tokens[1]
        total_cost, total_tokens = total_cost+cost, total_tokens+tokens
        history = vcat(history,(question, answer))
        # this runs a javascript function in the browser
        Base.run(__model__, raw"this.scrollToBottom()")
    end
    # When a new package is selected in the dropdown, load the associated index from disk
    @onchange index_in_use begin
        if !isfile("indexes/$index_in_use.jld2")
            notify(__model__, "Package not indexed.", :warning)
        else
        index = load("indexes/$index_in_use.jld2")["idx"]
        notify(__model__, "Index loaded.")
        end
    end
    # When the build index button is clicked, index the selected package and store the result
    @onbutton build_index begin
        index = build_index(eval(Symbol(index_in_use))) 
        @save "indexes/$index_in_use.jld2" index
        notify(__model__, "Index built and loaded.")
    end
    # update the LLM config when a new key is added
    @onchange openai_key begin
        kwargs = setpropertynested(AIHelpMe.RAG_KWARGS[],[:embedder_kwargs],:api_key,openai_key)
    end
    # erase chat history
    @onbutton reset_chat begin
         history = []
    end
end

@deps StippleMarkdown

# inject javascript method to scroll down the chat history
@methods begin
    """
    scrollToBottom: function() {
        const element = document.getElementById('scrollingDiv');
        element.scrollTop = element.scrollHeight;
    }
    """
end

@page("/", "app.jl.html")

