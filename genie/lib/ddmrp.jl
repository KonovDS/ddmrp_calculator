using XLSX, DataFrames, Dates, Statistics, Printf, Distributions, CategoricalArrays, Printf, CairoMakie

function data_categories(df)
    String.(levels(df[1, "sku"].pool)),
    extrema(df[:, "date"]),
    String.(levels(df[1, "loc"].pool))
end

function daily_filtered(df, skus, dates, locations)
    filtering = row -> begin
        row.loc ∈ locations && dates[1] <= row.date <= dates[2] && row.sku ∈ skus
    end

    daily_data = zeros(typeof(df[1, :qty]), (dates[2] - dates[1]).value + 1)
    
    for x in eachrow(filter(filtering , df))
        idx = (x.date - dates[1]).value + 1
        daily_data[idx] += x.qty
    end
    
    daily_data
end

# With periodic boundary condition
function sum_over_window(daily, window::Int)
    w = similar(daily)
    if size(w, 1) < window
        throw(ArgumentError("Incorrect window length"))
    end
    # Periodic conditions:
    w[1] = sum(daily[end - window + 2:end]) + daily[1]
    for i in 2:window
        w[i] = daily[i] + w[i - 1] - daily[end - window + i]
    end
    # Linear sweep:
    for i in window+1:size(daily, 1)
        w[i] = w[i - 1] + daily[i] - daily[i - window]
    end
    w
end

function ddmrp_sofia(daily_orders, pars)
    lt, moq, sl, red_safety, oc = pars
    # Using classic DDMRP:
    sum_w = sum_over_window(daily_orders, lt)
    μ = mean(daily_orders)
    σ = std(sum_w)

    z = quantile(Normal(), sl) 
    
    # Calculate:
    red    = (1 + red_safety) * σ * z
    yellow = μ * lt
    green  = max(oc * μ, moq)
    
    ceil(red), ceil(red) + ceil(yellow), ceil(red) + ceil(yellow) + ceil(green)
end

function ddmrp_other(daily_orders, pars)
    #for plotting:
    #return ddmrp_sofia(daily_orders, pars)
    lt, moq, sl, red_safety, oc = pars

    μ = mean(daily_orders)
    sum_w = sum_over_window(daily_orders, lt)
    # Using "numerical service level" idea:
    yellow = maximum(sum_w)
    green  = max(oc * μ, moq)

    0, ceil(yellow), ceil(yellow) + ceil(green)
end

function ddmrp_df_from_dfs(df_orders, df_params; only_sofia = false)
    # Parameters in the data:
    skus_orders, dates_orders, locs_orders = data_categories(df_orders)
    # Output columns:
    skus   = String[]
    skus2  = String[]
    locs   = String[]
    red    = Float64[]
    yellow = Float64[]
    green  = Float64[]
    # For simulator:
    simul_lt  = []
    simul_oc  = []
    simul_moq = [] 
    # Parsing task:
    for row in eachrow(df_params)
        for loc in locs_orders
            is_sofia = (loc == "Sofia")

            sku  = row["sku"]
            sku2 = row["sku_additional"]
            if (!(row["sku"] ∈ skus_orders) && !(row["sku_additional"] ∈ skus_orders)) || (!is_sofia && !(loc ∈ locs_orders))
                continue
            end
            if only_sofia && loc != "Sofia"
                continue
            end
            push!(skus, sku)
            push!(skus2, sku2)
            push!(locs, loc)

            # Necessary computations:
            lt  = is_sofia ? row["lt"] : row["lt_inner"]
            moq = is_sofia ? row["moq"] : row["moq_inner"]
            sl  = row["sl"]
            red_safety = row["red_safety"]
            oc = is_sofia ? row["oc"] : row["oc_inner"]
            loc = is_sofia ? locs_orders : [loc]

            # For simulator:
            push!(simul_lt, lt)
            push!(simul_oc, oc)
            push!(simul_moq, moq)
            
            # Computations:
            daily_orders = daily_filtered(df_orders, [sku, sku2], dates_orders, loc)
            redv, yellowv, greenv = is_sofia ? ddmrp_sofia(daily_orders, (lt, moq, sl, red_safety, oc)) : ddmrp_other(daily_orders, (lt, moq, sl, red_safety, oc))
            push!(red, ceil(redv))
            push!(yellow, ceil(yellowv))
            push!(green, ceil(greenv))
        end
    end
    # For simulator:
    dict = only_sofia ? Dict() : Dict(
        "Lead Time" => simul_lt,
        "Order Cycle" => simul_oc,
        "Minimum Order" => simul_moq
    )

    df = DataFrame(
        "Part Number" => skus,
        "Synonym Part Number" => skus2,
        "Office Location" => locs,
        dict...,
        "Red" => red,
        "Yellow" => yellow,
        "Green" => green,
        (only_sofia ? "Order Position" : "Initial Stock") => ["" for _ in 1:length(red)]
     )

     df
end