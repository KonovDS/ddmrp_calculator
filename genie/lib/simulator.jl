using XLSX, DataFrames, Dates, Statistics, Printf, Distributions, CategoricalArrays, Printf, CairoMakie

function day(op, oi, arrival, sales, moq, yellow_top, green_top; maxorder = 9999999, force = false, order_moq = false)
    # We count arrivals:
    oi += arrival
    # And try to satisfy demand:
    actual_sales = min(oi, sales)
    misses = sales - actual_sales
    op -= actual_sales
    oi -= actual_sales
    # Then, in the end of the day we order.
    # Either if we are in yellow:
    order = 0
    if op <= yellow_top
        order = min(green_top - op, maxorder)
    end
    # Or if we force-order (due to Order Cycle):
    if force
        order = min(green_top - op, maxorder)
        if order < moq
            if order_moq
                order = moq
            else
                order = 0
            end
        end
    end
    misses, op, oi, order
end

function simulator(daily_orders::NTuple{N, Vector{T}}, initial_stock::NTuple{N, T}, zones::NTuple{N, NTuple{3, T}}, lt::NTuple{N, Int}, oc::NTuple{N, Int}, moq::NTuple{N, T}; index_monday = 0, order_moq = false, sofia_orders_override = nothing) where {T, N}
    if index_monday < minimum(oc)
        throw("index_monday non conforming!")
    end
    if oc[1] != 0
        throw("Order cycle in sofia not implemented!")
    end
    days = length(daily_orders[1])

    # Output init:
    op_history = [zeros(days) for _ in 1:N] # Order Position
    oi_history = [zeros(days) for _ in 1:N] # On-hand Inventory
    mi_history = [zeros(days) for _ in 1:N] # Missed sales
    order_history = zeros(days) 

    ops = [x for x in initial_stock]
    ois = [x for x in initial_stock]
    for i in 1:days
        # Firstly for each warehouse except first:
        additional_sales = 0
        # Is it monday?
        for warehouse in 2:N
            force = false
            if oc[warehouse] != 0
                force = (oc[warehouse] % 7 == index_monday)
            end
            misses, op, oi, order = day(
                ops[warehouse],
                ois[warehouse],
                op_history[warehouse][i],
                daily_orders[warehouse][i],
                moq[warehouse],
                zones[warehouse][2],
                zones[warehouse][3];
                maxorder = ois[1] - additional_sales,
                force = force,
                order_moq = order_moq
            )
            # Placing orders:
            ops[warehouse] = op + order
            ois[warehouse] = oi
            # We must subtract this in Sofia:
            additional_sales += order
            if i + lt[warehouse] <= days
                op_history[warehouse][i + lt[warehouse]] = order
            end
            # Recording situation in the end of the day:
            op_history[warehouse][i] = ops[warehouse]
            oi_history[warehouse][i] = ois[warehouse]
            mi_history[warehouse][i] = misses
        end
        # Secondly, Sofia:
        misses, op, oi, order = day(
            ops[1],
            ois[1],
            op_history[1][i],
            daily_orders[1][i] + additional_sales,
            moq[1],
            zones[1][2],
            zones[1][3];
            maxorder = 9999999,
            force = false,
            order_moq = false
        )
        # sofia_orders_override:
        if !isnothing(sofia_orders_override)
            order = sofia_orders_override[i]
        end
        # Placing orders:
        ops[1] = op + order
        ois[1] = oi
        if i + lt[1] <= days
            op_history[1][i + lt[1]] = order
        end
        # Recording situation in the end of the day:
        order_history[i] = order
        op_history[1][i] = ops[1]
        oi_history[1][i] = ois[1]
        mi_history[1][i] = misses
    end
    op_history, oi_history, mi_history, order_history
end

function restock_filtered(df::DataFrame, sku, dates)
    filtering = row -> begin
        dates[1] <= row.ordered <= dates[2] && row.sku == sku
    end
    daily_data = zeros(typeof(df[1, :qty]), (dates[2] - dates[1]).value + 1)
    for x in eachrow(filter(filtering , df))
        idx = (x.ordered - dates[1]).value + 1
        daily_data[idx] += x.qty
    end
    daily_data
end

function simulator_from_dfs(df_orders, df_simulator, sku, df_orders_override = nothing)#; return_order_history = false, return_oi_history = false)
    # df sofia override:
    sofia_orders_override = nothing
    if !isnothing(df_orders_override)
        sofia_orders_override = restock_filtered(df_orders_override, sku, data_categories(df_orders)[2])
    end

    # Select all locations one-by-one (in order table) and generate daily sales:
    daily = []
    init  = []
    zones = []
    lt    = []
    oc    = []
    moq   = []

    warehouses = []

    skus_str_helper = []

    for row in eachrow(df_simulator)
        if row["sku"] != sku
            continue
        end
        if row["loc"] == "Sofia"
            my_push! = pushfirst!
        else 
            my_push! = push!
        end

        skus_str_helper = row["sku_additional"] != "" ? [row["sku"], row["sku_additional"]] : [row["sku"]]
        d = daily_filtered(df_orders, skus_str_helper, data_categories(df_orders)[2], [row["loc"]])
        
        my_push!(daily, d)
        my_push!(init , row["init"])
        my_push!(zones, (row["r"], row["y"], row["g"]))
        my_push!(lt   , row["lt_inner"])
        my_push!(oc   , row["oc"])
        my_push!(moq  , row["moq"])

        my_push!(warehouses, row["loc"] )
    end

    daily = tuple(daily...)
    init  = tuple(init...)
    zones = tuple(zones...)
    lt    = tuple(lt...)
    oc    = tuple(oc...)
    moq   = tuple(moq...)

    op_history, oi_history, mi_history, order_history = simulator(daily, init, zones, lt, oc, moq; index_monday = 0, order_moq = false, sofia_orders_override = sofia_orders_override)

    #=
    if return_order_history == true
        return order_history
    end
    if return_oi_history == true
        return order_history
    end
    =#
    
    str_skus = skus_str_helper[1]
    if length(skus_str_helper) > 1
        str_skus *= " ("
        str_skus *= join(skus_str_helper[2:end], ", ")
        str_skus *= ")"
    end

    num_of_orders = op_history .|> (op) -> begin
        orders = 0
        for i in 2:length(op)
            if op[i - 1] < op[i]
               orders += 1 
            end
        end
        orders
    end
    num_of_orders[1] = sum(order_history .|> (x) -> (x > 0 ? 1 : 0))

    text2 = [
        @sprintf("Total demand = %.0f, Incoming shippings = %d", sum(daily[i]), num_of_orders[i])
        for i in 1:length(daily)
    ]

    [simulator_plotter(zones[i], op_history[i], oi_history[i], mi_history[i]; date0=data_categories(df_orders)[2][1], title = @sprintf("Results for %s in %s (lead time = %d)", str_skus, warehouses[i], lt[i]), text2 = text2[i]) for i in 1:length(daily)]
end