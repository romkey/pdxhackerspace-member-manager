Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#index"

  get "/login", to: "sessions#new"
  post "/local_login", to: "sessions#create_local"
  post "/rfid_login", to: "sessions#create_rfid"
  delete "/logout", to: "sessions#destroy"
  match "/auth/:provider/callback", to: "sessions#create", via: %i[get post]
  get "/auth/failure", to: "sessions#failure"

  resources :users, only: [:index, :show, :edit, :update] do
    collection do
      post :sync
    end
  end

  resources :slack_users, only: [:index, :show] do
    collection do
      post :sync
      post :sync_to_users
    end
  end

  resources :sheet_entries, only: [:index, :show] do
    collection do
      post :sync
      post :sync_to_users
      get :test
    end
    member do
      post :sync_to_user
    end
  end

  resources :paypal_payments, only: [:index, :show] do
    collection do
      post :sync
    end
  end

  resources :recharge_payments, only: [:index, :show] do
    collection do
      post :sync
      get :test
    end
  end

  resources :journals, only: [:index]

  resources :access_logs, only: [:index] do
    collection do
      get :generate_users_json
    end
  end

  get "/search", to: "search#index", as: :search

  get "/settings", to: "settings#index", as: :settings
  resources :training_topics, only: [:index, :create, :destroy]
end
