Rails.application.routes.draw do
  root "clips#index"
  resources :clips, only: [:index, :show, :create, :update, :destroy]
end
