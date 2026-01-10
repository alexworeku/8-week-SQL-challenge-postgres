set search_path=pizza_runner;



/* Clean and transform tables
 * --------------------------------------------
 * Customer_Orders Table
 * --------------------------------------------
 */

create temp table temp_cleaned_customer_orders as
select
	row_number() over (order by co.order_id) as order_item_id,
	co.order_id,
	co.customer_id,
	co.pizza_id,
	case
		when co.exclusions in ('null','','NaN') then null
		else co.exclusions
	end as exclusions,
	case
		when co.extras in ('null','','NaN') then null
		else co.extras
	end as extras,
	co.order_time
from customer_orders co; 
/*  
 *--------------------------------------------
 * Runner_Orders Table
 * --------------------------------------------
 */

create temp table temp_cleaned_runner_orders as
select 
	order_id,
	runner_id,
	case 
		when ro.pickup_time in ('null','') then null 
		else ro.pickup_time
		end as pickup_time,
	case 
		when ro.distance in ('null','') then null
		else regexp_replace(ro.distance,'[^0-9.]','','g')::numeric 
	end as distance_km,
	case 
		when ro.duration in ('null','') then null
		else regexp_replace(ro.duration,'[^0-9.]','','g')::numeric 
	end as duration_min,
	case 
		when ro.cancellation in ('null','NaN','') then null
		else ro.cancellation
	end as cancellation
	
from runner_orders ro;

/*  
 *--------------------------------------------
 * Customer_Orders Table - Topic Modification
 * --------------------------------------------
 */

create temp table order_ingredient_modification as 
select
	cco.order_item_id,
	cco.order_id,
	cco.customer_id,
	cco.pizza_id,
	transformed_data.ingredient_id,
	transformed_data.mod_type,
	cco.order_time
from temp_cleaned_customer_orders cco
left join lateral (
	select
		'exclusion' as mod_type,
		trim(unnest(string_to_array(cco.exclusions,',')))::numeric as ingredient_id
	
		union all
	
	select
		'extra' as mod_type,
		trim(unnest(string_to_array(cco.extras,',')))::numeric as ingredient_id

) as transformed_data on true;





/*
 * ---------------------------------
 *  A. Pizza Metrics
 *----------------------------------
*/

-- 1. How many pizzas were ordered?

select 
	count(*) as n_pizzas_ordered

from temp_cleaned_customer_orders tcco;


-- 2. How many unique customer orders were made?

select
	count(distinct tcco.order_id) as n_unique_orders
from temp_cleaned_customer_orders tcco;

-- 3. How many successful orders were delivered by each runner?

select 
	tcro.runner_id,
	count(*) as n_orders_delivered
from temp_cleaned_runner_orders tcro
where tcro.cancellation is null
group by tcro.runner_id
order by n_orders_delivered desc;

-- 4. How many of each type of pizza was delivered?
with delivery_count_by_pizza_type as (
select 
	tcco.pizza_id,
	count(*) as n_delivery
from temp_cleaned_customer_orders tcco
join temp_cleaned_runner_orders tcro on tcro.order_id = tcco.order_id
where tcro.cancellation is null
group by tcco.pizza_id
)

select 
	pn.pizza_name,
	dcbpt.n_delivery
from delivery_count_by_pizza_type dcbpt
join pizza_names pn on pn.pizza_id = dcbpt.pizza_id
order by dcbpt.n_delivery desc;

-- 5. How many Vegetarian and Meatlovers were ordered by each customer?
select 
	cco.customer_id,
	count(case when cco.pizza_id = 1 then true else null end) as n_meat_lovers_pizzas,
	count(case when cco.pizza_id = 2 then true else null end) as n_veg_pizzas
from temp_cleaned_customer_orders cco
group by cco.customer_id; 


-- 6. What was the maximum number of pizzas delivered in a single order?

with number_of_pizzas_delivered_per_order as (
select 
	tcco.order_id,
	count(tcco.pizza_id) as n_pizzas_delivered
from temp_cleaned_customer_orders tcco
join temp_cleaned_runner_orders tcro on tcco.order_id = tcro.order_id
where tcro.cancellation is null
group by tcco.order_id
),
delivery_count_ranked as (
select 
	npdpo.order_id,
	npdpo.n_pizzas_delivered,
	dense_rank() over (order by npdpo.n_pizzas_delivered desc) as rnk
from number_of_pizzas_delivered_per_order npdpo
)
select 
	dcr.order_id,
	dcr.n_pizzas_delivered,
	dcr.rnk 
from delivery_count_ranked dcr
where dcr.rnk =1;

-- 7. For each customer, how many delivered pizzas had at least 1 change and how many had no changes?

select 
	tcco.customer_id,
	count(tcco.pizza_id) as n_pizzas_delivered,
	count(case when tcco.exclusions is null and tcco.extras is null then true else null end) as n_unchanged_pizzas,
	count(case when tcco.exclusions is not null or tcco.extras is not null then true else null end) as n_changed_pizzas
from  temp_cleaned_customer_orders tcco
join  temp_cleaned_runner_orders tcro on tcco.order_id = tcro.order_id
where tcro.cancellation is null
group by tcco.customer_id;

-- 8. How many pizzas were delivered that had both exclusions and extras?
select 
count(tcco.order_id) as n_pizzas_with_exclusion_and_extra_delivered
from  temp_cleaned_customer_orders tcco
join  temp_cleaned_runner_orders tcro on tcco.order_id = tcro.order_id
where tcro.cancellation is null and (tcco.exclusions is not null and tcco.extras is not null);

-- 9. What was the total volume of pizzas ordered for each hour of the day?

select 
	date_part('hour',tcco.order_time) as hour_of_day,
	count(tcco.order_id) as n_pizzas_ordered
from temp_cleaned_customer_orders tcco
group by date_part('hour',tcco.order_time)
order by n_pizzas_ordered desc;

-- 10.What was the volume of orders for each day of the week?

select 
	trim(to_char(tcco.order_time,'day')) as day_of_week,
	count (tcco.order_id) as n_pizzas_ordered
from temp_cleaned_customer_orders tcco
group by trim(to_char(tcco.order_time,'day'))
order by n_pizzas_ordered desc;





/*
 * ---------------------------------
 * B. Runner and Customer Experience
 *----------------------------------
*/

--1. How many runners signed up for each 1 week period? (i.e. week starts 2021-01-01)

select 
to_char(rn.registration_date,'WW') as week_num,
count(*) as n_runners	
from runners rn
group by to_char(rn.registration_date,'WW')
order by n_runners desc;

--2. What was the average time in minutes it took for each runner to arrive at the Pizza Runner HQ to pickup the order?
with pickup_duration_by_runner as (
select

distinct tcco.order_id,
tcro.runner_id,
round((date_part( 'epoch',tcro.pickup_time::timestamp - tcco.order_time::timestamp)/60)::numeric,2) as pickup_duration_min
from temp_cleaned_runner_orders tcro 
join temp_cleaned_customer_orders tcco on tcro.order_id = tcco.order_id
where cancellation is null
)
select 
pdr.runner_id,
round(avg(pickup_duration_min),2) as avg_pickup_duration_min

from pickup_duration_by_runner pdr
group by pdr.runner_id
order by avg_pickup_duration_min;



--3. Is there any relationship between the number of pizzas and how long the order takes to prepare?

with pizza_count_with_prep_duration as (
select 
	tcco.order_id,
	count(tcco.pizza_id) as n_pizzas,
	date_part('epoch',max(tcro.pickup_time::timestamp) - max(tcco.order_time::timestamp)) as order_prep_duration

from temp_cleaned_customer_orders tcco
join temp_cleaned_runner_orders tcro on tcco.order_id = tcro.order_id
where tcro.cancellation is null
group by tcco.order_id
),
pizza_count_and_prep_duration_correlation as (
select
	corr(pcpd.n_pizzas,pcpd.order_prep_duration) as correlation
from pizza_count_with_prep_duration pcpd
)
select 
    case 
        when abs(pcpdc.correlation) < 0.20 then 'No meaningful linear relationship'
        
  
        when pcpdc.correlation >= 0.70 then 'Yes: Strong positive relationship'
        when pcpdc.correlation <= -0.70 then 'Yes: Strong negative relationship'
        
        when pcpdc.correlation > 0 then 'Yes: Weak to moderate positive relationship'
        when pcpdc.correlation < 0 then 'Yes: Weak to moderate negative relationship'
        
        else 'Relationship inconclusive'
    end as relation

from pizza_count_and_prep_duration_correlation pcpdc;

--4.  What was the average distance travelled for each customer?

with individual_customer_orders as (
select 
	distinct tcco.order_id,
	tcco.customer_id
from temp_cleaned_customer_orders tcco
)
select
	ico.customer_id,
	round(avg(tcro.distance_km::numeric),2) as avg_distance_km
from individual_customer_orders ico
join temp_cleaned_runner_orders tcro on ico.order_id = tcro.order_id
where tcro.cancellation is null
group by ico.customer_id;

--5. What was the difference between the longest and shortest delivery times for all orders?

with max_and_min_delivery_times as (
select
max(tcro.duration_min::numeric) as longest_delivery_time_min,
min(tcro.duration_min::numeric) as shortest_delivery_time_min
from temp_cleaned_runner_orders tcro
where tcro.cancellation is null
)
select 
mdt.longest_delivery_time_min,
mdt.shortest_delivery_time_min,
mdt.longest_delivery_time_min - mdt.shortest_delivery_time_min as difference
from max_and_min_delivery_times mdt;

--6. What was the average speed for each runner for each delivery and do you notice any trend for these values?


select 
	tcro.runner_id,
	tcro.order_id,
	tcro.pickup_time,
	tcro.distance_km,
	tcro.duration_min,
	round(tcro.distance_km/(tcro.duration_min/60),2) as speed_kmh,
	round(avg(tcro.distance_km/(tcro.duration_min/60.0)) over(partition by tcro.runner_id),2) as avg_speed_kmh
from temp_cleaned_runner_orders tcro
where tcro.cancellation is null
order by tcro.runner_id, tcro.pickup_time;

--7. What is the successful delivery percentage for each runner?

with delivery_count_by_runner as (
select
	tcro.runner_id,
	count(*) filter( where tcro.cancellation is null) as n_orders_delivered,
	count(*) as  n_orders
from temp_cleaned_runner_orders tcro
group by tcro.runner_id
)
select
	dcr.runner_id,
	(dcr.n_orders_delivered::numeric/dcr.n_orders) * 100 as success_percentage

from delivery_count_by_runner dcr
order by success_percentage desc;

/*
 * ---------------------------------
 * C. Ingredient Optimisation
 *----------------------------------
*/

--1. What are the standard ingredients for each pizza?
with pizza_recipe_with_names as (
select 
	pr.pizza_id,
	pn.pizza_name,	
	trim(unnest(string_to_array(pr.toppings,',')))::numeric as topping_id
from pizza_recipes pr
join pizza_names pn on pr.pizza_id =pn.pizza_id 

)

select
	
	prwn.pizza_name,
	string_agg(pt.topping_name,', ')

from pizza_recipe_with_names prwn
join pizza_toppings pt on prwn.topping_id = pt.topping_id
group by prwn.pizza_name;


--2. What was the most commonly added extra?
with extra_toppings_usage_count as (
select pt.topping_name,
	count(*) as n_usage,
	dense_rank() over (order by count(*) desc) as rnk
from order_ingredient_modification oim
join pizza_toppings pt on oim.ingredient_id = pt.topping_id
where oim.mod_type = 'extra' and oim.ingredient_id is not null
group by pt.topping_name 
)
select 
	etuc.topping_name,
	etuc.n_usage
from extra_toppings_usage_count etuc
where  etuc.rnk=1;


--3. What was the most common exclusion?
with extra_toppings_usage_count as (
select pt.topping_name,
	count(*) as n_usage,
	dense_rank() over (order by count(*) desc) as rnk
from order_ingredient_modification oim
join pizza_toppings pt on oim.ingredient_id = pt.topping_id
where oim.mod_type = 'exclusion' and oim.ingredient_id is not null
group by pt.topping_name 
)
select 
	etuc.topping_name,
	etuc.n_usage
from extra_toppings_usage_count etuc
where  etuc.rnk=1;


--4. Generate an order item for each record in the customers_orders table in the format of one of the following
	--	Meat Lovers
	--	Meat Lovers - Exclude Beef
	--	Meat Lovers - Extra Bacon
	--	Meat Lovers - Exclude Cheese, Bacon - Extra Mushroom, Peppers

select *
from order_ingredient_modification t;

with order_items_with_ingredients as (
select 
	 oim.order_id,
	oim.order_item_id,
	oim.pizza_id,
	string_agg(pt.topping_name,', ') filter (where mod_type='exclusion') as exclusion,
	string_agg(pt.topping_name,', ') filter (where mod_type='extra') as extra
from  order_ingredient_modification oim
left join pizza_toppings pt on pt.topping_id  = oim.ingredient_id
group by oim.order_item_id,oim.pizza_id,oim.order_id
)
select
	oiwi.order_item_id,
	pn.pizza_name || coalesce(' - Exclude ' || oiwi.exclusion,'') || coalesce(' - Extra ' || oiwi.extra,'') as order_item
	
from order_items_with_ingredients oiwi
join pizza_names pn on pn.pizza_id =oiwi.pizza_id
order by oiwi.order_item_id;

--5. Generate an alphabetically ordered comma separated ingredient list for each pizza order from the customer_orders table and add a 2x in front of any relevant ingredients
--	For example: "Meat Lovers: 2xBacon, Beef, ... , Salami"
with order_items_with_ingredients as (
select 
tcco.order_item_id,
unnest (array(
	select trim(unnest(string_to_array(pr.toppings,',')))
	except
	select trim(unnest(string_to_array(tcco.exclusions,',')))
	union all
	select trim(unnest(string_to_array(tcco.extras,',')))
))::integer as ingredient_id

from temp_cleaned_customer_orders tcco
join pizza_recipes pr on pr.pizza_id =tcco.pizza_id

), 

ingredients_with_quantity as( 

select 
oii.order_item_id,
oii.ingredient_id,
count(oii.ingredient_id) as quantity

from order_items_with_ingredients oii
group by oii.order_item_id,oii.ingredient_id
order by oii.order_item_id
)

select 


iwq.order_item_id,
pn.pizza_name || ': ' ||
string_agg(
case 
	when iwq.quantity > 1 then concat(iwq.quantity,'x',pt.topping_name)
	else pt.topping_name
end 
,', ' order by pt.topping_name)as ingredient

from ingredients_with_quantity iwq
join temp_cleaned_customer_orders tcco on tcco.order_item_id = iwq.order_item_id
join pizza_names pn on pn.pizza_id =tcco.pizza_id
join pizza_toppings pt on pt.topping_id =iwq.ingredient_id
group by iwq.order_item_id,pn.pizza_name;

--6. What is the total quantity of each ingredient used in all delivered pizzas sorted by most frequent first?


with order_items_with_ingredients as (
select 
tcco.order_item_id,
unnest (array(
	select trim(unnest(string_to_array(pr.toppings,',')))
	except
	select trim(unnest(string_to_array(tcco.exclusions,',')))
	union all
	select trim(unnest(string_to_array(tcco.extras,',')))
))::integer as ingredient_id

from temp_cleaned_customer_orders tcco
join pizza_recipes pr on pr.pizza_id =tcco.pizza_id
join temp_cleaned_runner_orders tcro on tcco.order_id = tcro.order_id
where tcro.cancellation is null
)

select 
pt.topping_name,
count(oii.ingredient_id) as total_quantity_used

from order_items_with_ingredients oii
join pizza_toppings pt on pt.topping_id =oii.ingredient_id
group by pt.topping_name
order by total_quantity_used desc;


/*
 * ---------------------------------
 * D. Pricing and Ratings
 *----------------------------------
*/
-- 1. If a Meat Lovers pizza costs $12 and Vegetarian costs $10 and there were no charges for changes 
--- how much money has Pizza Runner made so far if there are no delivery fees?

select 
	sum (case 
		when tcco.pizza_id = 1 then 12
		when  tcco.pizza_id = 2 then 10
		else 0
	end) as total_income_usd
from temp_cleaned_customer_orders tcco
join temp_cleaned_runner_orders tcro on tcco.order_id = tcro.order_id
join pizza_names pn on pn.pizza_id = tcco.pizza_id
where tcro.cancellation is null;



-- 2. What if there was an additional $1 charge for any pizza extras?
--		- Add cheese is $1 extra
with delivered_orders as (
select
	tcco.order_item_id,
	tcco.order_id,
	tcco.pizza_id
from temp_cleaned_customer_orders tcco
join temp_cleaned_runner_orders tcro on tcco.order_id = tcro.order_id
where tcro.cancellation is null),

base_revenue as (

select sum (case  when d.pizza_id = 1 then 12 else 10 end) as base_total
from delivered_orders d
),

extra_revenue as (
select count(*) as extra_total
from order_ingredient_modification oim
where oim.mod_type = 'extra' and ingredient_id = 4
)

select (br.base_total + er.extra_total) total_revenue_usd
from base_revenue br, extra_revenue er;



--3. The Pizza Runner team now wants to add an additional ratings system that allows customers to rate their runner, 
-- how would you design an additional table for this new dataset 
-- generate a schema for this new table and insert your own data for ratings for each successful customer order between 1 to 5.

create table runner_ratings (
order_id numeric not null,
runner_id numeric not null,
rating numeric(1,0) not null check(rating between 0 and 5)
);

insert into runner_ratings(order_id, runner_id, rating)
select tcro.order_id, tcro.runner_id, floor(random()*6) as rating
from temp_cleaned_runner_orders tcro
where tcro.cancellation is null;


--4. Using your newly generated table - can you join all of the information together to form a table which has the following information for successful deliveries?
		--customer_id
		--order_id
		--runner_id
		--rating
		--order_time
		--pickup_time
		--Time between order and pickup
		--Delivery duration
		--Average speed
		--Total number of pizzas

select 
	distinct tcco.order_id,
	tcco.customer_id,
	tcro.runner_id,
	rr.rating,
	tcco.order_time,
	tcro.pickup_time,
	date_part('minute',	tcro.pickup_time::timestamp - tcco.order_time::timestamp) as order_prep_duration,
	tcro.duration_min,
	round(tcro.distance_km/ (tcro.duration_min/60),2)  as speed_kmh,
	count(pizza_id) over (partition by tcco.order_id)as n_pizzas
	
from temp_cleaned_customer_orders tcco
join temp_cleaned_runner_orders tcro on tcco.order_id = tcro.order_id
join runner_ratings rr on rr.order_id = tcco.order_id
where tcro.cancellation is null;


--5. If a Meat Lovers pizza was $12 and Vegetarian $10 fixed prices with no cost for extras and each runner is paid $0.30 per kilometre traveled 
-- how much money does Pizza Runner have left over after these deliveries?


with runner_earnings as (
select 
	sum(round(tcro.distance_km *0.3,2)) as total_earning_usd
from temp_cleaned_runner_orders tcro
where tcro.cancellation is null),
 pizza_runner_earnings as (
select 
	sum (case 
		when tcco.pizza_id = 1 then 12
		when  tcco.pizza_id = 2 then 10
		else 0
	end) as revenue_usd
from temp_cleaned_customer_orders tcco
join temp_cleaned_runner_orders tcro on tcco.order_id = tcro.order_id
join pizza_names pn on pn.pizza_id = tcco.pizza_id
where tcro.cancellation is null

)

select 
	pre.revenue_usd,
	re.total_earning_usd,
	pre.revenue_usd - re.total_earning_usd  as net_income_usd
from runner_earnings re, pizza_runner_earnings pre;